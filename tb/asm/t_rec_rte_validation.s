; AP68020 exception recovery: an RTE whose format B frame is not readable to its end takes a bus error, it does not halt
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
 lea $6000,sp
 move.w #$2700,(sp)
 move.l #fail,2(sp)
 move.w #$B008,6(sp)
 clr.w $36(sp)
 move.l #$6058,BERRREG
 rte
 bra fail
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
 bra pass
