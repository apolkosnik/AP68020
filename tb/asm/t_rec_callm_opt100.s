; AP68020 module call: CALLM opt 100 with a stack change copies no arguments
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
 move.l #$AABBCCDD,$6000-28  ; just below where the frame belongs
 move.l #$CAFEBABE,a5
 callm #4,desc
 cmp.l #$6000-24,d0         ; the frame right below the new SP: no argument space
 bne fail
 cmp.l #$11223344,d2        ; the argument, reached through the saved SP
 bne fail
 move.l $6000-24+$14,d1     ; the frame's saved SP: the caller's argument
 cmp.l #$7000-4,d1
 bne fail
 move.l $6000-28,d1         ; nothing stored below the frame
 cmp.l #$AABBCCDD,d1
 bne fail
 cmp.l #$7000,sp
 bne fail
 bra pass
module:
 dc.w $D000
 move.l sp,d0
 move.l $14(sp),a0          ; opt 100: the arguments stay on the calling stack
 move.l (a0),d2
 rtm a5
 cnop 0,4
desc:
 dc.l $81C30000,module,$8000,$6000
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
