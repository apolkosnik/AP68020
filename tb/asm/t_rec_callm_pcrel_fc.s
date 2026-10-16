; AP68020 module call: a PC-relative CALLM descriptor is announced in program space
; (MC68020 UM 9.8; from an independent audit's reproducer)
; assembled with vasmm68k_mot -Fbin -m68020
FAILREG equ $F00100
DONEREG equ $F00102
 org 0
 dc.l $7000,start
 rept 254
 dc.l unexpected
 endr
 org $400
start:
 move.b #1,$F001D4
 move.b #1,$F001D5
 move.l #desc,$F001C0
 callm #0,desc(pc)
 moveq #0,d0
 move.w $F001C4,d0
 cmp.w #6,d0
 bne fail
 move.l $F001D4,d1
 and.l #7,d1
 cmp.l d0,d1
 bne fail
 bra pass
module:
 dc.w $D000
 rtm a5
 org $1000
desc:
 dc.l $01C30000,module,$8000
pass:
 move.w #$600D,DONEREG
 bra.s pass
fail:
 move.w #1,FAILREG
 move.w #$BAD0,DONEREG
 bra.s fail
unexpected:
 move.w #99,FAILREG
 move.w #$BAD0,DONEREG
 bra.s unexpected
