; AP68020 exception recovery: stage B supplied by the handler (RB cleared) is kept while stage C is refetched
; (MC68020 UM 6.1.7, 6.2.1; from an independent audit's reproducer)
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
 moveq #0,d0
 moveq #0,d2
 move.l #target,BERRREG
 jsr target
 cmp.l #42,d0
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
 addq.l #1,d2
 cmp.l #1,d2
 bne fail
 move.w #$702A,$E(sp)
 andi.w #$EFFF,$A(sp)
 clr.l BERRREG
 rte
 org $8000
target:
 nop
 moveq #7,d0
 rts
