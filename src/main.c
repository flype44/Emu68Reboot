/******************************************************************************
 * 
 * Project: Emu68Reboot
 * Author:  Philippe CARPENTIER
 * 
 * Flush Tests:
 * Echo "Hello world!" >  Hello.txt && Emu68Reboot
 * Echo "Hello world!" >  Hello.txt && Emu68Reboot DISKFLUSH
 * Echo "Hello world!" >> Hello.txt && Emu68Reboot 
 * Echo "Hello world!" >> Hello.txt && Emu68Reboot DISKFLUSH
 * 
 *****************************************************************************/

#include <dos/dos.h>
#include <dos/dosextens.h>
#include <exec/exec.h>
#include <proto/dos.h>
#include <proto/exec.h>
#include <proto/devicetree.h>

#include "LE32.h"
#include "main.h"

/*****************************************************************************
 * 
 * DEFINES
 * 
 *****************************************************************************/

#define PM_WDOG_MAGIC   (0x5A000000)
#define PM_RSTC_FULLRST (0x00000020)
#define PM_RSTC ((volatile ULONG*)(0xF2000000 + 0x0010001C))
#define PM_RSTS ((volatile ULONG*)(0xF2000000 + 0x00100020))
#define PM_WDOG ((volatile ULONG*)(0xF2000000 + 0x00100024))

#define GARY_COLDBOOT_REG ((volatile UBYTE *)0x00DE0002)
#define GARY_COLDBOOT_BIT 0x80

#define TEMPLATE "DELAY/N,DISKFLUSH/S,KILLEXEC/S,COLDREBOOT/S,HELP/S"

typedef enum {
	OPT_DELAY,
	OPT_DISKFLUSH,
	OPT_KILLEXEC,
	OPT_COLDREBOOT,
	OPT_HELP,
	OPT_COUNT
} OPT_ARGS;

/*****************************************************************************
 * 
 * GLOBALS
 * 
 *****************************************************************************/

STRPTR VerString = VERSTRING;

APTR DeviceTreeBase = NULL;

extern struct ExecBase   * SysBase;
extern struct DosLibrary * DOSBase;

/*****************************************************************************
 * 
 * Help()
 * 
 *****************************************************************************/

STATIC VOID Help(VOID)
{
	Printf("%s\n%s\n\n%s\n", VerString + 6, TEMPLATE,
	"DELAY      : Delay in seconds, before waiting for disk activity\n"
	"DISKFLUSH  : Flush pending file system writes before waiting for disk activity\n"
	"KILLEXEC   : Kill ExecBase before rebooting\n"
	"COLDREBOOT : AmigaOS standard reboot\n"
	"HELP       : Print this help\n"
	);
}

/*****************************************************************************
 *
 * FlushPendingDiskWrites()
 * Best-effort: asks every mounted volume to write back cached modifications
 * (e.g. delayed writes on PFS/SFS). Failures are silently ignored, since
 * ACTION_FLUSH is not guaranteed to be honored by every file system.
 *
 *****************************************************************************/

STATIC VOID FlushPendingDiskWrites(VOID)
{
	struct DosList * dol;

	dol = LockDosList(LDF_VOLUMES | LDF_READ);

	while (dol = NextDosEntry(dol, LDF_VOLUMES | LDF_READ))
	{
		if (CheckSignal(SIGBREAKF_CTRL_C))
		{
			break;
		}

		if (dol->dol_Task)
		{
			DoPkt(dol->dol_Task, ACTION_FLUSH, 0, 0, 0, 0, 0);
		}
	}

	UnLockDosList(LDF_VOLUMES | LDF_READ);
}

/*****************************************************************************
 *
 * WaitForDiskActivity()
 * Returns FALSE if aborted by CTRL_C (no reboot should happen in that case).
 * Returns TRUE once every mounted volume is confirmed idle.
 *
 *****************************************************************************/

STATIC BOOL WaitForDiskActivity(VOID)
{
	for (;;)
	{
		struct DosList * dol;
		BOOL busy = FALSE;

		if (CheckSignal(SIGBREAKF_CTRL_C))
		{
			return (FALSE);
		}

		dol = LockDosList(LDF_VOLUMES | LDF_READ);

		while (dol = NextDosEntry(dol, LDF_VOLUMES | LDF_READ))
		{
			if (dol->dol_Task)
			{
				struct InfoData info;

				if (DoPkt(dol->dol_Task, ACTION_DISK_INFO, 
					MKBADDR(&info), 0, 0, 0, 0))
				{
					if (info.id_DiskState == ID_VALIDATING)
					{
						busy = TRUE;
						break;
					}
				}
			}
		}

		UnLockDosList(LDF_VOLUMES | LDF_READ);

		if (!busy)
		{
			return (TRUE);
		}

		Delay(50);
	}
}

/*****************************************************************************
 *
 * Emu68Reboot()
 *
 *****************************************************************************/

STATIC VOID Emu68Reboot(BOOL kill)
{
	ULONG rsts;
	
	/* Disable AmigaOS interrupts */
	Disable();
	
	/* Clear AmigaOS ExecBase address */
	if (kill != FALSE)
	{
		*((volatile ULONG *)(0x00000004)) = NULL;
	}
	
	/* RPi-Watchdog mechanism */
	rsts = asm_le32(*PM_RSTS) & ~0xfffffaaa;
	*PM_RSTS = asm_le32(PM_WDOG_MAGIC | rsts);
	*PM_WDOG = asm_le32(PM_WDOG_MAGIC | 10);
	*PM_RSTC = asm_le32(PM_WDOG_MAGIC | PM_RSTC_FULLRST);
	
	/* Infinite loop */
	for (;;);
}

/*****************************************************************************
 * 
 * Entry point
 * 
 *****************************************************************************/

ULONG main(ULONG argc, STRPTR * argv)
{
	ULONG rc;
	LONG opts[OPT_COUNT];
	struct RDArgs * rdargs;
	
	opts[OPT_DELAY     ] = 0L;
	opts[OPT_DISKFLUSH ] = 0L;
	opts[OPT_KILLEXEC  ] = 0L;
	opts[OPT_COLDREBOOT] = 0L;
	opts[OPT_HELP      ] = 0L;
	
	if (rdargs = (struct RDArgs *)ReadArgs(TEMPLATE, opts, NULL))
	{
		rc = RETURN_OK;
		
		if (opts[OPT_HELP] != NULL)
		{
			Help();
		}
		else
		{
			ULONG seconds = 1;
			
			/* DELAY */
			if (opts[OPT_DELAY] != NULL)
			{
				seconds = *(ULONG *)opts[OPT_DELAY];
				
				if (seconds < 1)
				{
					seconds = 1;
				}
			}
			
			Delay(seconds * 50);

			/* DISKFLUSH */
			if (opts[OPT_DISKFLUSH] != NULL)
			{
				FlushPendingDiskWrites();
			}

			/* Wait for any ongoing drive write/validation to finish. */
			if (WaitForDiskActivity())
			{
				/* Force a genuine cold-boot hardware reinit on the 
				** next reset, on real Gayle-equipped Amiga. */
				*GARY_COLDBOOT_REG |= GARY_COLDBOOT_BIT;

				/* COLDREBOOT */
				if (opts[OPT_COLDREBOOT] != NULL)
				{
					ColdReboot();
				}

				/* EMU68REBOOT */
				if (DeviceTreeBase = (struct Library *)OpenResource(DEVICETREE_NAME))
				{
					Emu68Reboot((BOOL)(opts[OPT_KILLEXEC] != NULL));
				}
				else
				{
					Printf("Cant open " DEVICETREE_NAME "!\n");
					rc = RETURN_ERROR;
				}
			}
			else
			{
				PutStr("Aborted, reboot cancelled.\n");
				rc = RETURN_FAIL;
			}
		}
		
		FreeArgs(rdargs);
	}
	else
	{
		PutStr("Bad argument, use HELP for more information.\n");
		rc = RETURN_FAIL;
	}
	
	return (rc);
}

/*****************************************************************************
 * 
 * END OF FILE
 * 
 *****************************************************************************/
