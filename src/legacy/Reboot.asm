;------------------------------------------------------------------------------
;
; Disassembling of the C:Reboot command V45+ (AmigaOS 3.1.4+)
;
;------------------------------------------------------------------------------
;
; > CD RAM:
; > C:ira -M68000 -A -PREPROC C:Reboot
;
; IRA V2.09 (06.03.18)
; (c)1993-1995 Tim Ruehsen (SiliconSurfer/PHANTASM)
; (c)2009-2015 Frank Wille
; (c)2014-2017 Nicolas Bastien
;
; SOURCE : "C:Reboot"
; TARGET : "Reboot.asm"
; MACHINE: MC68000
; OFFSET : $00000000
; Pass 0: scanning for data in code
; Areas:    1
; codeAdrs: 0   codeAdrMax: 16
; CodeArea[0]: 00000000 - 000000d8
; CodeArea[1]: 00000104 - 00000104
;
; Pass 1: 100%
; Pass 2: correcting labels
; Pass 2: writing mnemonics
; 100%
;
;------------------------------------------------------------------------------
;
; ALGORITHM SUMMARY
;
;   1. Open dos.library V37. If that fails, skip straight to the reboot (no DOS
;      means nothing to wait for).
;   2. Loop:
;        - CheckSignal(SIGBREAKF_CTRL_C) -- if the user hit CTRL_C, abort with
;          RETURN_FAIL, no reboot happens.
;        - LockDosList(LDF_VOLUMES|LDF_READ) and walk every mounted VOLUME
;          entry (NOT the device list -- flags value 9 = LDF_VOLUMES(1<<3) |
;          LDF_READ(1<<0), confirmed against dos/dosextens.h's LDB_VOLUMES=3 /
;          LDB_READ=0; a device-list read would have been flags=5).
;        - For every volume with a live handler (dol_Task != NULL), send it
;          ACTION_DISK_INFO (25) via DoPkt() with a local struct InfoData as
;          arg1 (converted to a BPTR with the classic >>2, i.e. MKBADDR()).
;        - If id_DiskState == ID_VALIDATING (81), mark "busy" and stop
;          scanning immediately -- one busy volume is enough to keep waiting.
;        - UnLockDosList(). If nothing was busy, fall through to the reboot.
;          Otherwise Delay(50) (1 second) and go back to step 2 -- forever,
;          no timeout, only CTRL_C can get out of this loop.
;   3. Set the Gary/Gayle-compatible "coldboot" hardware flag (bit 7 of
;      $00DE0002) so the upcoming reset is a genuine cold boot (full hardware
;      reinit) rather than a soft reset. This is the SAME register A3000/A4000's
;      Fat Gary implements at the same address for backward compatibility;
;      Gayle (A600/A1200/CD32's combined IDE+PCMCIA+Gary-compatibility chip)
;      implements it too. On any model without Gayle/Gary (A500/A1000/A2000/
;      CDTV), this address is simply unmapped bus space: the write is a
;      harmless no-op, which is exactly why the official command never
;      bothers checking the model first.
;   4. Exec -> ColdReboot(). Never returns.
;
;------------------------------------------------------------------------------
;
; See :
;
; exec.library
;   OpenLibrary, CloseLibrary, ColdReboot
; dos.library
;   CheckSignal, LockDosList, UnLockDosList, NextDosEntry, DoPkt, Delay
; dos/dosextens.h
;   struct DosList (dol_Task at offset 8), ACTION_DISK_INFO (25),
;   LDF_VOLUMES/LDF_READ (LDB_VOLUMES=3, LDB_READ=0 -> flags 9 = both)
; dos/dos.h
;   struct InfoData (id_DiskState at offset 8), ID_VALIDATING (81),
;   MKBADDR() (raw pointer -> BPTR, i.e. >>2)
;
;------------------------------------------------------------------------------

ABSEXECBASE	EQU	$4

	SECTION S_0,CODE

SECSTRT_0:

	SUBA.W	#$002c,A7		; Reserve 44 bytes of local stack space
	MOVEM.L	D2-D7/A3-A6,-(A7)	; Push callee-saved registers
	MOVEQ	#0,D7			; D7 = "aborted by CTRL_C" flag, 0 = no

	LEA	LAB_0008(PC),A1		; A1 = "dos.library"
	MOVEQ	#37,D0			; D0 = version
	MOVEA.L	ABSEXECBASE.W,A6	; A6 = ExecBase
	JSR	-552(A6)		; Exec -> OpenLibrary("dos.library", 37)
	MOVEA.L	D0,A5			; A5 = DOSBase
	TST.L	D0			; Check result
	BEQ.W	LAB_0006		; DOS unavailable -> skip the wait entirely, reboot now

	; Reserve a local `struct InfoData info;` (36 bytes) within the 44-byte
	; block reserved above, 4-byte aligned: A0 = A7+47 lands inside that
	; block, ANDI.W #$fffc rounds the address down to a 4-byte boundary.
	; This is ordinary compiler-generated local-variable layout, nothing
	; algorithmically meaningful -- equivalent to a plain C local variable.
	LEA	47(A7),A0		; A0 = raw address of the local InfoData buffer
	MOVE.L	A0,D0			; D0 = that address
	ANDI.W	#$fffc,D0		; Round down to 4-byte alignment
	MOVEA.L	D0,A4			; A4 = &info (aligned)

LAB_0000:
	MOVEQ	#0,D6			; D6 = "a volume is still validating" flag, 0 = no

	MOVEQ	#64,D1			; D1 = 64
	LSL.L	#6,D1			; D1 = 64 << 6 = 4096 = SIGBREAKF_CTRL_C
	MOVEA.L	A5,A6			; A6 = DOSBase
	JSR	-792(A6)		; DOS -> CheckSignal(SIGBREAKF_CTRL_C)
	TST.L	D0			; Check result
	BEQ.S	LAB_0001		; No break pending -> proceed to LockDosList

	MOVEQ	#1,D7			; D7 = 1 (aborted by CTRL_C)
	BRA.S	LAB_0005		; -> CloseLibrary, then FAIL (no reboot)

LAB_0001:
	MOVEQ	#9,D1			; D1 = LDF_VOLUMES(8) | LDF_READ(1) = 9
	JSR	-654(A6)		; DOS -> LockDosList(LDF_VOLUMES|LDF_READ)
	MOVEA.L	D0,A3			; A3 = struct DosList * (opaque lock handle)
	BRA.S	LAB_0003		; -> first NextDosEntry

LAB_0002:
	MOVE.L	8(A3),D0		; D0 = dol->dol_Task (offset 8 of struct DosList)
	BEQ.S	LAB_0003		; No live handler for this entry -> skip it

	MOVE.L	A4,D1			; D1 = &info
	ASR.L	#2,D1			; D1 = MKBADDR(&info)  (raw pointer -> BPTR, >>2)
	MOVE.L	D1,40(A7)		; Stash the BPTR on the stack for the DoPkt() call below

	MOVEM.L	D6-D7,-(A7)		; Save D6 (busy flag) / D7 (abort flag) across the call
	MOVE.L	D0,D1			; D1 = port = dol->dol_Task
	MOVE.L	48(A7),D3		; D3 = arg1 = MKBADDR(&info) (offset shifted by the push above)
	MOVEQ	#25,D2			; D2 = action = ACTION_DISK_INFO
	MOVEQ	#0,D4			; D4 = arg2 = 0
	MOVE.L	D4,D5			; D5 = arg3 = 0
	MOVE.L	D4,D6			; D6 = arg4 = 0
	MOVE.L	D4,D7			; D7 = arg5 = 0
	MOVEA.L	A5,A6			; A6 = DOSBase
	JSR	-240(A6)		; DOS -> DoPkt(dol_Task, ACTION_DISK_INFO, MKBADDR(&info), 0,0,0,0)
	MOVEM.L	(A7)+,D6-D7		; Restore D6/D7
	TST.L	D0			; DoPkt() failed (handler didn't answer)?
	BEQ.S	LAB_0003		; Yes -> skip this entry

	MOVEQ	#81,D0			; D0 = ID_VALIDATING
	CMP.L	8(A4),D0		; Compare against info.id_DiskState (offset 8 of InfoData)
	BNE.S	LAB_0003		; Not validating -> check the next entry

	MOVEQ	#1,D6			; D6 = 1 (a volume is still validating)
	BRA.S	LAB_0004		; One is enough -- stop scanning, go unlock

LAB_0003:
	MOVE.L	A3,D1			; D1 = current struct DosList * (lock handle / previous entry)
	MOVEQ	#9,D2			; D2 = LDF_VOLUMES|LDF_READ (same flags as the lock)
	MOVEA.L	A5,A6			; DOSBase
	JSR	-690(A6)		; DOS -> NextDosEntry(dlist, LDF_VOLUMES|LDF_READ)
	MOVEA.L	D0,A3			; A3 = next entry (or NULL)
	TST.L	D0			; More entries?
	BNE.S	LAB_0002		; Yes -> examine it

LAB_0004:
	MOVEQ	#9,D1			; D1 = LDF_VOLUMES|LDF_READ (must match the lock's flags)
	MOVEA.L	A5,A6			; A6 = DOSBase
	JSR	-660(A6)		; DOS -> UnLockDosList(LDF_VOLUMES|LDF_READ)
	TST.W	D6			; Was a volume still validating?
	BEQ.S	LAB_0005		; No -> proceed to CloseLibrary, then reboot

	MOVEQ	#50,D1			; D1 = 50 ticks (1 second)
	JSR	-198(A6)		; DOS -> Delay(50)
	TST.W	D6			; (redundant re-check of the same D6 -- always still 1 here)
	BNE.S	LAB_0000		; Loop back to the top: re-scan every volume from scratch

LAB_0005:
	MOVEA.L	A5,A1			; A1 = DOSBase
	MOVEA.L	ABSEXECBASE.W,A6	; A6 = ExecBase
	JSR	-414(A6)		; Exec -> CloseLibrary(DOSBase)

LAB_0006:
	TST.W	D7			; Aborted by CTRL_C earlier?
	BNE.S	LAB_0007		; Yes -> RETURN_FAIL, no reboot

	; Gary/Gayle-compatible motherboard resource configuration register,
	; bit 7 = "coldboot" flag. Setting it forces the upcoming reset to be
	; treated as a genuine cold boot (full hardware reinit) instead of a
	; soft reset. Same register/address A3000/A4000's Fat Gary implements;
	; Gayle (A600/A1200/CD32) implements it too, for compatibility. On any
	; other model (A500/A1000/A2000/CDTV) this address is unmapped bus
	; space, so the write is a harmless no-op -- which is exactly why this
	; code never bothers checking the model first.
	MOVEA.L	#$00de0002,A0		; A0 = Gary/Gayle "coldboot" config register
	BSET	#7,(A0)			; Set bit 7 (byte-wide op on a memory operand)

	MOVEA.L	ABSEXECBASE.W,A6	; A6 = ExecBase
	JSR	-726(A6)		; Exec -> ColdReboot()  -- never returns

LAB_0007:
	MOVEQ	#20,D0			; D0 = RETURN_FAIL
	MOVEM.L	(A7)+,D2-D7/A3-A6	; Pop callee-saved registers
	ADDA.W	#$002c,A7		; Release the local stack space
	RTS				; Exit

LAB_0008:
	DC.B	"dos.library",0
	DC.B	"$VER: reboot 45.1 (25.11.2017)",0,0
	END
