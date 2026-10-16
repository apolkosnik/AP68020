; AP68020 exception recovery: a software-completed MOVEM.W read sign-extends the supplied word
; (MC68020 UM 6.1.7, 6.1.12, 6.2; from an independent audit's reproducer)
; assembled with vasmm68k_mot -Fbin -m68020
FAILREG equ $F00100
DONEREG equ $F00102
BERRREG equ $F00130
 org 0
 dc.l $7000,start
 dc.l h_bus
 rept 253
 dc.l unexpected
 endr
 org $400
start:
 lea $404000,a0
 move.l a0,BERRREG
 movem.w (a0),d0
 cmp.l #$FFFF8001,d0
 bne fail
 bra pass
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
h_bus:
 move.l #$8001,$2C(sp)
 andi.w #$FEFF,$A(sp)
 rte
