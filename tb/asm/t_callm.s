; AP68020 module call and return: CALLM and RTM (MC68020 UM 9.7/9.8,
; M68000 PRM 4-64 and 4-167)
; assembled with vasmm68k_mot -Fbin -m68020
;
;   - type $00, opt 000: the module stack frame (opt/type/access, CCR,
;     argument count, descriptor, PC, saved data area register, saved SP),
;     the entry word's register loaded with the data area pointer, the
;     arguments just above the frame; RTM restores CCR, the register and the
;     PC and removes the frame and the arguments
;   - a data register, opt 100, a PC-relative descriptor; A7 as the
;     entry/RTM register (the stack pointer prevails)
;   - format errors (vector 14, PC = the instruction, nothing changed): opt,
;     type and user types $10-$1F in the descriptor, opt/type in the RTM
;     frame, type $01 without access control hardware (CPU space BERR)
;   - type $01 with the bench's access control model: CAL saved in the
;     frame, the descriptor address (with its FC) and IAL written, the access
;     status read; status 1, status 4 (a new stack, the arguments copied),
;     status 0 and 8 refused; RTM writes the DAL
;
; protocol with the bench (tb_ap020_program.sv):
;   word write to $F00100 = failing test number
;   word write to $F00102 = $BAD0 on failure, $600D when all tests passed
;   $F001D4/$F001D5 (byte writes): access control model enable, status
;   $F001D4 long read: IAL, DAL, 0, descriptor FC; $F001D8: descriptor

FAILREG	equ	$F00100
DONEREG	equ	$F00102
ACEN	equ	$F001D4
ACSTAT	equ	$F001D5
ACREGS	equ	$F001D4
ACDESC	equ	$F001D8

lastvec	equ	$3800		; word: vector number of the last exception
lastpc	equ	$3804		; long: its stacked PC
resume	equ	$3808		; long: where the handler returns
modsp	equ	$3810		; long: A7 inside the module
modreg	equ	$3814		; long: the entry register inside the module
modarg	equ	$3818		; long: the first argument longword inside the module
NEWSTK	equ	$2C00		; type $01 stack change: the module's stack

failt	macro
	move.w	#\1,d7
	bra	fail_all
	endm

chkl	macro
	cmp.l	#\2,\1
	beq.s	ok\@
	failt	\3
ok\@:
	endm

chkw	macro
	cmp.w	#\2,\1
	beq.s	ok\@
	failt	\3
ok\@:
	endm

	org	0
	dc.l	$3400		; initial ISP
	dc.l	start
	rept	12
	dc.l	unexp
	endr
	dc.l	h_fmt		; 14 format error
	rept	241
	dc.l	unexp
	endr

	org	$400
start:
;---------------------------------------------------------------- type $00, opt 000, A5
	move.l	#$AAAA5555,a5
	move.w	#$1234,-(sp)		; arguments: 4 bytes
	move.w	#$5678,-(sp)
	move.l	sp,d5			; SP before the CALLM
	move.w	#$2715,sr		; CCR X Z C
c1:	callm	#4,desc1
c1r:	move.w	sr,d0
	and.w	#$1F,d0
	chkw	d0,$15,1		; CCR from the frame
	move.l	a5,d0
	chkl	d0,$AAAA5555,2		; A5 restored
	move.l	sp,d0
	sub.l	d5,d0
	chkl	d0,4,3			; the frame and the arguments removed
	move.l	modreg,d0
	chkl	d0,data1,4		; A5 = data area pointer in the module
	move.l	modsp,a0
	move.l	d5,d1
	sub.l	#24,d1
	cmp.l	a0,d1
	beq.s	t5
	failt	5			; the frame on top of the calling stack
t5:	move.l	(a0),d0
	chkl	d0,$00000015,6		; opt 000, type $00, access 0, CCR $15
	move.l	4(a0),d0
	chkl	d0,$00040000,7		; argument count 4
	move.l	8(a0),d0
	chkl	d0,desc1,8
	move.l	12(a0),d0
	chkl	d0,c1r,9		; the PC after the CALLM
	move.l	16(a0),d0
	chkl	d0,$AAAA5555,10		; the saved A5
	move.l	20(a0),d0
	cmp.l	d5,d0
	beq.s	t11
	failt	11			; the saved SP
t11:	move.l	modarg,d0
	chkl	d0,$56781234,12		; the arguments above the frame

;---------------------------------------------------------------- D3, opt 100, PC-relative descriptor
	move.l	#$11112222,d3
	move.l	sp,d5
	move.w	#$2708,sr		; CCR N
c2:	callm	#0,desc2(pc)
c2r:	move.w	sr,d4			; the CCR RTM restored
	chkl	d3,$11112222,20		; D3 restored
	move.l	sp,d0
	cmp.l	d5,d0
	beq.s	t21
	failt	21
t21:	move.l	modreg,d0
	chkl	d0,data2,22
	move.l	modsp,a0
	move.l	(a0),d0
	chkl	d0,$80000008,23		; opt 100, CCR N
	and.w	#$1F,d4
	chkw	d4,$08,24		; the module's CCR change undone

;---------------------------------------------------------------- A7 as the data area register
	move.l	sp,d5
	callm	#0,desc3
	move.l	sp,d0
	cmp.l	d5,d0
	beq.s	t30
	failt	30			; SP back, the saved data pointer lost
t30:	move.l	d5,d1
	sub.l	#24,d1
	move.l	modreg,d0
	cmp.l	d1,d0
	beq.s	t31
	failt	31			; A7 in the module = the frame, not the data pointer
t31:

;---------------------------------------------------------------- format errors
	move.l	#$CAFE0000,a5
	move.l	sp,d5
	move.l	#f1,resume
f0:	callm	#0,descbad1		; opt 001
f1:	chkw	lastvec,14,40
	move.l	lastpc,d0
	chkl	d0,f0,41
	move.l	a5,d0
	chkl	d0,$CAFE0000,42		; nothing changed
	move.l	sp,d0
	cmp.l	d5,d0
	beq.s	t43
	failt	43
t43:	clr.w	lastvec
	move.l	#f3,resume
f2:	callm	#0,descbad2		; type $02
f3:	chkw	lastvec,14,44
	clr.w	lastvec
	move.l	#f5,resume
f4:	callm	#0,descbad3		; type $10: disabled by the user
f5:	chkw	lastvec,14,45
	clr.w	lastvec
	move.l	#f7,resume
	move.l	#$40000000,-(sp)	; a module frame with opt 010
	move.l	sp,d5
f6:	rtm	a5
f7:	chkw	lastvec,14,46
	move.l	lastpc,d0
	chkl	d0,f6,47
	move.l	sp,d0
	cmp.l	d5,d0
	beq.s	t48
	failt	48			; RTM changed nothing
t48:	addq.l	#4,sp
	clr.w	lastvec
	move.l	#f9,resume
f8:	callm	#0,desc11		; type $01, no access control hardware: BERR
f9:	chkw	lastvec,14,49
	move.l	lastpc,d0
	chkl	d0,f8,50

;---------------------------------------------------------------- type $01, access status 1
	move.b	#1,ACEN
	move.b	#1,ACSTAT
	move.l	#$BBBB0000,a5
	move.l	sp,d5
	callm	#0,desc11
	move.l	a5,d0
	chkl	d0,$BBBB0000,60
	move.l	sp,d0
	cmp.l	d5,d0
	beq.s	t61
	failt	61
t61:	move.l	modsp,a0
	move.l	(a0),d0
	and.l	#$FFFF0000,d0
	chkl	d0,$015A0000,62		; type $01, the saved CAL $5A
	move.l	ACDESC,d0
	chkl	d0,desc11,63		; the descriptor address
	move.l	ACREGS,d0
	chkl	d0,$C35A0005,64		; IAL $C3 (the descriptor), DAL $5A (RTM), FC 5

;---------------------------------------------------------------- type $01, access status 4: a new stack
	move.b	#4,ACSTAT
	move.w	#$9ABC,-(sp)
	move.w	#$DEF0,-(sp)
	move.l	sp,d5
	callm	#4,desc12
	move.l	sp,d0
	sub.l	d5,d0
	chkl	d0,4,70			; the old stack, arguments removed
	move.l	modsp,d0
	chkl	d0,NEWSTK-4-24,71	; the frame below the copied arguments
	move.l	modarg,d0
	chkl	d0,$DEF09ABC,72		; the arguments copied
	move.l	NEWSTK-4-24+20,d0
	cmp.l	d5,d0
	beq.s	t73
	failt	73			; the saved SP: the old stack
t73:

;---------------------------------------------------------------- refused: access status 0 and 8
	move.l	sp,d5
	move.b	#0,ACSTAT
	clr.w	lastvec
	move.l	#r1,resume
	callm	#0,desc11
r1:	chkw	lastvec,14,80
	move.b	#8,ACSTAT
	clr.w	lastvec
	move.l	#r2,resume
	callm	#0,desc11
r2:	chkw	lastvec,14,81
	move.l	sp,d0
	cmp.l	d5,d0
	beq.s	t82
	failt	82
t82:	move.b	#0,ACEN

	move.w	#$600D,DONEREG
	stop	#$2700

;---------------------------------------------------------------- modules
	cnop	0,4
mod1:	dc.w	$D000			; A5
	move.l	sp,modsp
	move.l	a5,modreg
	move.l	24(sp),modarg
	move.w	#0,ccr
	rtm	a5

mod2:	dc.w	$3000			; D3
	move.l	sp,modsp
	move.l	d3,modreg
	move.l	#$DEAD,d3
	move.w	#$1F,ccr
	rtm	d3

mod3:	dc.w	$F000			; A7
	move.l	sp,modreg
	rtm	a7

mod11:	dc.w	$D000			; A5
	move.l	sp,modsp
	move.l	24(sp),modarg
	rtm	a5

;---------------------------------------------------------------- descriptors
	cnop	0,4
desc1:	dc.l	$00000000,mod1,data1
desc2:	dc.l	$80000000,mod2,data2
desc3:	dc.l	$00000000,mod3,data1
descbad1: dc.l	$20000000,mod1,data1
descbad2: dc.l	$02000000,mod1,data1
descbad3: dc.l	$10000000,mod1,data1
desc11:	dc.l	$01C30000,mod11,data1
desc12:	dc.l	$01C30000,mod11,data1,NEWSTK
data1:	dc.l	0
data2:	dc.l	0

;---------------------------------------------------------------- handlers
h_fmt:	move.w	6(sp),d0
	and.w	#$0FFF,d0
	lsr.w	#2,d0
	move.w	d0,lastvec
	move.l	2(sp),lastpc
	move.l	resume,2(sp)
	rte

fail_all:
	move.w	d7,FAILREG
	move.w	#$BAD0,DONEREG
halt1:	bra.s	halt1

unexp:	move.w	#$00FF,FAILREG
	move.w	#$BAD0,DONEREG
halt2:	bra.s	halt2
