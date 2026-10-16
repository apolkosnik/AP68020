; AP68020 module call: CALLM opt 000 with a stack change copies the arguments
; (MC68020 UM 9.7.1; from an independent audit's reproducer)
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
 move.b #4,$F001D5
 move.l #$11223344,-(sp)
 move.l #$AABBCCDD,$5FFC
 move.l #$CAFEBABE,a5
 callm #4,desc
 cmp.l #$6000-28,d0
 bne fail
 cmp.l #$11223344,$5FFC
 bne fail
 cmp.l #$7000,sp
 bne fail
 bra pass
module:
 dc.w $D000
 move.l sp,d0
 rtm a5
 cnop 0,4
desc:
 dc.l $01C30000,module,$8000,$6000
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
