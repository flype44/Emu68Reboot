# **Emu68Reboot** version 1.1

## **NAME**

```
	EMU68REBOOT - Reboots your Amiga.
```

## **FORMAT**

```
	EMU68REBOOT [<DELAY seconds>] [DISKFLUSH] [KILLEXEC] [COLDREBOOT] [HELP]
```

## **TEMPLATE**

```
	DELAY/N,DISKFLUSH/S,KILLEXEC/S,COLDREBOOT/S,HELP/S
```

## **PATH**

```
	C:EMU68REBOOT
```

## **PREAMBULE**

```
	EMU68REBOOT is an AmigaOS CLI command for PiStorm/Emu68 setups. Unlike a
	plain AmigaOS reboot, it fully reboots the Raspberry Pi host running
	Emu68 -- reloading its firmware and re-reading the SD card's boot
	configuration -- instead of only resetting the emulated Amiga side.
	It requires the Emu68 JIT baremetal emulator to work properly, unless
	the COLDREBOOT option is used.
```

## **FUNCTION**

```
	EMU68REBOOT can be used in scripts to fully reboot an Amiga fitted with a
	PiStorm accelerator card. Alternatively, if asked, it can perform a
	standard AmigaOS reboot instead, through Exec's ColdReboot() function.

	By default this is a very low-level operation: it tells the Raspberry Pi
	to reboot by forcing its firmware to reinitialize the hardware.

	It is particularly useful after updating the Emu68/PiStorm firmware, or
	after editing configuration files on the Raspberry Pi's primary BOOT
	partition.

	Just like the AmigaOS REBOOT command (V45+), it waits for any ongoing
	drive write operation to finish before rebooting, to avoid file system
	validation issues. As with the real REBOOT command, this wait has no
	timeout: it polls once a second for as long as any volume still reports
	itself as validating, and can only be interrupted with CTRL_C, which
	cancels the reboot entirely.

	The DELAY option inserts an extra pause, in seconds, before that
	disk-activity wait begins.

	The DISKFLUSH option asks every mounted volume to write back any pending
	cached modifications (e.g. delayed writes on file systems such as PFS or
	SFS) before the disk-activity wait begins. This is a best-effort
	operation: failures on individual volumes are silently ignored.

	The KILLEXEC option clears the ExecBase pointer before rebooting the RPi.

	Just like the official REBOOT command, it also sets the Gary/Gayle-
	compatible "coldboot" hardware flag (bit 7 of $DE0002) right before
	rebooting, forcing a genuine cold hardware reinit on the next boot on
	real A600/A1200/CD32 machines. On any other model (A500/A1000/A2000/
	CDTV), this is a harmless no-op, since none of them decode that address.

	The COLDREBOOT option performs a standard AmigaOS reboot instead of a
	Raspberry Pi reboot.

	If no option is given, the command reboots the Raspberry Pi.

	The HELP option displays a short help text.
```

## **RETURN CODES**

```
	FAIL    (20) Bad argument, or the disk-activity wait was cancelled with CTRL_C
	ERROR   (10) Can't open devicetree.resource
	SUCCESS (0)  No error
```

## **EXAMPLES**

```
	1> C:EMU68REBOOT
```

Waits for disk activity to finish, then reboots the Raspberry Pi.

```
	1> C:EMU68REBOOT DELAY 5
```

Waits 5 seconds, then for disk activity to finish, then reboots the Raspberry Pi.

```
	1> C:EMU68REBOOT DISKFLUSH
```

Flushes pending file system writes, then waits for disk activity to finish,
then reboots the Raspberry Pi.

```
	1> C:EMU68REBOOT KILLEXEC
```

Clears ExecBase, then reboots the Raspberry Pi.

```
	1> C:EMU68REBOOT COLDREBOOT
```

Waits for disk activity to finish, then performs a standard AmigaOS reboot.

```
	1> C:EMU68REBOOT HELP
	Emu68Reboot 1.1 (9.9.2026) [SAS/C 6.59] Philippe CARPENTIER
	DELAY/N,DISKFLUSH/S,KILLEXEC/S,COLDREBOOT/S,HELP/S

	DELAY      : Delay in seconds, before waiting for disk activity
	DISKFLUSH  : Flush pending file system writes before waiting for disk activity
	KILLEXEC   : Kill ExecBase before rebooting
	COLDREBOOT : AmigaOS standard reboot
	HELP       : Print this help
```

## **SEE ALSO**

```
	REBOOT, EMU68INFO HARDRESET
```
