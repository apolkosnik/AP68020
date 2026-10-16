; AP68020 exception recovery: a software-completed MOVES.B read (DIB supplied, DF cleared) merges a byte into D0
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
 moveq #5,d0
 movec d0,sfc
 lea $404000,a0
 move.l a0,BERRREG
 move.l #$12345678,d0
 moves.b (a0),d0
 cmp.l #$123456AB,d0
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
 move.l #$AB,$2C(sp)
 andi.w #$FEFF,$A(sp)
 rte
