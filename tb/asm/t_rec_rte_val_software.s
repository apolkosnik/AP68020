; AP68020 exception recovery: an RTE validation read completed by software (DF cleared) still completes the RTE
; (MC68020 UM 6.1.12, 6.2.1, 6.2.2; from an independent audit's reproducer)
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
 moveq #0,d2
 move.l #$12345678,$204000
 move.l #$404000,BERRREG
 move.l $404000,d0
 cmp.l #$12345678,d0
 bne fail
 cmp.l #2,d2
 bne fail
 bra pass
h_bus:
 addq.l #1,d2
 cmp.l #1,d2
 bne second
 move.l sp,d3
 add.l #88,d3
 move.l d3,BERRREG
 rte
 bra fail
second:
 cmp.l #2,d2
 bne fail
 clr.l BERRREG
 move.l $B4(sp),d3
 move.l d3,$2C(sp)
 andi.w #$FEFF,$A(sp)
 rte
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
