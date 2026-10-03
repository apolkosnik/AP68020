; AP68020 in MC68020-compatible mode (ap020_top cpu020 = 1; bench CPU020=1)
; assembled with vasmm68k_mot -Fbin -m68020 -m68851
;
;   - CACR keeps only E (bit 0) and F (bit 1); the 68030's data cache,
;     burst and write-allocate bits read as zero (Kickstart's 68030 test:
;     the data cache enable does not stick)
;   - no MMU: PMOVE, PFLUSHA and PTEST are coprocessor-ID-0 instructions;
;     with no MC68851 answering they take Line F (vector 11, format 0,
;     stacked PC = the instruction), in user mode as well (no privilege
;     check of their own)
;   - the hidden data cache: E enables it (a read hit ignores memory
;     changed behind it), C clears it, without E every read is a bus read
;   - the instruction cache: data writes do not update it, C clears it, CE
;     clears the entry CAAR selects
;
; The RAM aliases at $200000 (16-bit port), so memory can be written
; behind the logical caches.
;
; protocol with the bench (tb_ap020_program.sv):
;   word write to $F00100 = failing test number
;   word write to $F00102 = $BAD0 on failure, $600D when all tests passed

FAILREG	equ	$F00100
DONEREG	equ	$F00102
W16	equ	$200000
CFGREG	equ	$F001D0		; bench build: bit 0 FAST_PORT, bit 1 DATA_CACHE

exccnt	equ	$3800		; word: exceptions taken
lastvec	equ	$3802		; word: vector number of the last exception
lastpc	equ	$3804		; long: its stacked PC
lastfv	equ	$3808		; word: its format/vector word
skip	equ	$380C		; long: added to the stacked PC by the handler

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
	rept	254
	dc.l	h_exc
	endr

	org	$400
start:
	clr.w	exccnt
	clr.l	skip

;---------------------------------------------------------------- CACR: the 68020's bits only
	moveq	#-1,d0
	movec	d0,cacr
	movec	cacr,d1
	chkl	d1,$00000003,1		; E and F
	move.l	#$00003310,d0		; IBE ED FD DBE WA: none exist
	movec	d0,cacr
	movec	cacr,d1
	chkl	d1,$00000000,2
	move.l	#$00000101,d0		; Kickstart: does the data cache enable stick?
	movec	d0,cacr
	movec	cacr,d1
	btst	#8,d1
	beq.s	cr_ok
	failt	3
cr_ok:	chkl	d1,$00000001,4
	moveq	#0,d0
	movec	d0,cacr

;---------------------------------------------------------------- no MMU: Line F
	lea	$3000,a0
	move.l	#4,skip
	clr.w	exccnt
mm1:	pmove	tc,(a0)
	chkw	exccnt,1,10
	chkw	lastvec,11,11
	chkw	lastfv,$002C,12		; format 0, vector 11
	move.l	lastpc,d0
	chkl	d0,mm1,13
mm2:	pflusha
	chkw	exccnt,2,14
	move.l	lastpc,d0
	chkl	d0,mm2,15
mm3:	ptestr	#1,(a0),#7
	chkw	exccnt,3,16
	move.l	lastpc,d0
	chkl	d0,mm3,17
mm4:	pmove	(a0),tc
	chkw	exccnt,4,18
	move.l	lastpc,d0
	chkl	d0,mm4,19
	; user mode: still Line F, not a privilege violation
	lea	$3300,a1
	move.l	a1,usp
	andi.w	#$DFFF,sr		; to user mode
mm5:	pmove	tc,(a0)
	clr.l	skip
	trap	#0			; back to supervisor (the handler sets S)
	chkw	exccnt,6,20
	move.l	lastpc,d0		; the trap's frame is the last one: check
	move.w	$3810,d1		; the Line F vector saved before it
	chkw	d1,11,21
	move.l	$3812,d0
	chkl	d0,mm5,22

;---------------------------------------------------------------- the hidden data cache
; it holds native-port memory only (FAST_PORT, with DATA_CACHE): with both,
; a read hit ignores memory changed behind it; otherwise every data read
; is a bus read, as on the MC68020
	move.w	CFGREG,d4
	and.w	#3,d4
	cmp.w	#3,d4
	beq.s	dc_on
	moveq	#1,d0			; E: no data cache to see
	movec	d0,cacr
	move.l	#$11111111,($4010).l
	move.l	($4010).l,d1
	chkl	d1,$11111111,30
	move.l	#$22222222,W16+$4010	; memory behind
	move.l	($4010).l,d1		; read from memory
	chkl	d1,$22222222,31
	bra	dc_done
dc_on:	moveq	#1,d0			; E
	movec	d0,cacr
	move.l	#$11111111,($4010).l
	move.l	($4010).l,d1		; miss: allocated
	chkl	d1,$11111111,30
	move.l	#$22222222,W16+$4010	; memory only
	move.l	($4010).l,d1		; hit: the cached value
	chkl	d1,$11111111,31
	move.l	#$33333333,($4010).l	; write hit: updated (write-through)
	move.l	($4010).l,d1
	chkl	d1,$33333333,32
	move.l	W16+$4010,d1
	chkl	d1,$33333333,33
	move.l	#$44444444,W16+$4010
	moveq	#1+8,d0			; E, C: both caches cleared
	movec	d0,cacr
	move.l	($4010).l,d1
	chkl	d1,$44444444,34
	moveq	#0,d0			; caches off: every read from memory
	movec	d0,cacr
	move.l	#$55555555,W16+$4010
	move.l	($4010).l,d1
	chkl	d1,$55555555,35
dc_done:

;---------------------------------------------------------------- the instruction cache
	moveq	#1+8,d0			; E, C
	movec	d0,cacr
	moveq	#0,d3
	bsr	smc
	chkl	d3,1,40
	move.w	#$7605,smc+2		; moveq #5,d3: a data write
	moveq	#0,d3
	bsr	smc
	chkl	d3,1,41			; the cached code runs
	moveq	#1+8,d0			; C
	movec	d0,cacr
	moveq	#0,d3
	bsr	smc
	chkl	d3,5,42
	move.w	#$7607,smc+2
	moveq	#0,d3
	bsr	smc
	chkl	d3,5,43			; stale again
	lea	smc+2,a0
	move.l	a0,d0
	movec	d0,caar
	moveq	#1+4,d0			; CE: the entry of CAAR
	movec	d0,cacr
	moveq	#0,d3
	bsr	smc
	chkl	d3,7,44
	moveq	#0,d0
	movec	d0,cacr

	move.w	#$600D,DONEREG
	stop	#$2700

smc:
	nop
	moveq	#1,d3
	rts

fail_all:
	moveq	#0,d0
	movec	d0,cacr
	move.w	d7,FAILREG
	move.w	#$BAD0,DONEREG
fa:	bra.s	fa

;---------------------------------------------------------------- handler
; frame: 0(sp) SR, 2(sp) PC, 6(sp) format/vector.  The previous exception's
; vector and PC are kept at $3810/$3812 (the user-mode test reads them
; after its TRAP).  TRAP #0 returns in supervisor mode.
h_exc:
	move.w	lastvec,$3810
	move.l	lastpc,$3812
	move.l	d6,-(sp)
	move.w	10(sp),d6
	move.w	d6,lastfv
	and.w	#$0FFF,d6
	lsr.w	#2,d6
	move.w	d6,lastvec
	move.l	6(sp),lastpc
	addq.w	#1,exccnt
	cmp.w	#32,d6
	bne.s	h_n
	or.w	#$2000,4(sp)		; TRAP #0: back to supervisor
h_n:	move.l	skip,d6
	add.l	d6,6(sp)
	move.l	(sp)+,d6
	rte
