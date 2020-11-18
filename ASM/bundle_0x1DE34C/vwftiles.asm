vwftiles: ; big
	movem.l d1-a5,-(sp)
	lea $19aec0,a4 ; char gfx
	lea $19adc0,a5 ; char width
vwftiles_main:
	; Save current position to stack, should remove that
	move.w d0,-(sp)
	move.w d0,d4
	lsr.w #3,d0
	jsr $1492
	move.w $ffff96b8.w,d5	
;	move.w $ffff96ba.w,d7
.readtile_readletter:
	movea.l a4,a1
	lsl.w #5,d3
	adda.w d3,a1
	lsr.w #5,d3
	move.w $ffff858e.w,d4
	divu #$08,d4
	clr.w d4
	swap d4
	bsr.w .readletter
.readtile_readwidth:
	moveq #$00,d2
	movea.l a5,a1
	move.b $00(a1,d3.w),d2
	; Add current letter with to number stored in stack
	add.w d2,(sp)
	move.w d2,$ffff858c.w
	bsr .printchars_checkpos
.readtile_prepare:
	lsl.w #5,d3
	lea $ffff96c5.w,a2
	move.l $ffff85a4.w,a3
	move.w $ffff858e.w,d2
	lsr.w #$3,d2
	move.w d2,d6
	moveq #$0,d7
.readtile_part1:
	move.w #$0c10,(a3)+
	move.w d6,d2
	lsl.w #5,d2
	add.w d5,d2
	move.w d2,(a3)+
	move.w #$20,(a3)+
	move.w #$10,d2
	move.l $ffffa6c8.w,a1
	jsr $228a
.readtile_part2:
	move.w #$0c10,(a3)+
	move.w d6,d2
	lsl.w #5,d2
	move.w $ffff96ba.w,d4 ;
	lsl.w #4,d4 ;
	add.w d4,d2 ;
	add.w d5,d2
	move.w d2,(a3)+
	move.w #$20,(a3)+
	move.w #$10,d2
	move.l $ffffa6c8.w,a1
	lea $20(a1),a1
	jsr $228a
.readtile_check_window:
	moveq #$0,d2
	move.w $ffff858e.w,d2
	lsr #$03,d2
	moveq #$0,d4
	move.w $ffff858e.w,d4
	add.w $ffff858c.w,d4
	lsr #$03,d4
	sub.w d2,d4
	move.b d4,d7
.readtile_move_window:
	tst.w d7
	beq .readtile_vram_part1
	moveq #$8,d4
	bsr.w .moveletter
	sub.w #$1,d7
	tst.w d7
	beq .readtile_vram_part1
	moveq #$8,d4
	bsr.w .moveletter
.readtile_vram_part1:
	lsr.w #5,d5
	add.w $ffff96be.w,d5
	move.w d6,d1
	add.w d5,d1
	move.w #$0c10,(a3)+
	move.w d0,(a3)+
	move.w #$1,(a3)+
	; Quick hack for two tiles traversal
	;tst.w d7
	;beq .readtile_vram_part1_finish
	addq.w #1,-$2(a3)
	move.w d1,(a3)+
	addq.w #1,d1
.readtile_vram_part1_finish:
	move.w d1,(a3)+
.readtile_vram_part2:
	move.w d6,d1
	move.w $ffff96ba.w,d4 ;
	lsr.w #1,d4 ;
	add.w d4,d1 ;
	add.w d5,d1
	move.w #$0c10,(a3)+
	addi.w #$80,d0
	move.w d0,(a3)+
	move.w #$1,(a3)+
	; Quick hack for two tiles traversal
	;tst.w d7
	;beq .readtile_vram_part2_finish
	addq.w #1,-$2(a3)
	move.w d1,(a3)+
	addq.w #1,d1
.readtile_vram_part2_finish:
	move.w d1,(a3)+
.readtile_save_results:
	move.l a3,$ffff85a4.w
	move.w $ffff858c.w,d0
	bsr .printchars_checkpos
    add.w d0,$ffff858e.w
	move.w (sp)+,d0
	movem.l (sp)+,d1-a5
	rts

.readletter:
	move.l $ffffa6c8.w,a2
	moveq #$f,d2
.readletter_repeat:
	moveq #$0,d1
	move.w (a1)+,d1
	swap.w d1
	lsr.l d4,d1
	or.l d1,(a2)+
	dbf d2,.readletter_repeat
	rts

.moveletter:
	move.l $ffffa6c8.w,a2
	moveq #$f,d2
.moveletter_repeat:
	move.l (a2),d1
	lsl.l d4,d1
	move.l d1,(a2)+
	dbf d2,.moveletter_repeat
	rts

.printchars_checkpos:
	move d3,-(sp)
	moveq #$0,d3
	move $ffff858e.w,d3
	;add $ffff858c.w,d3
	add.w #$08,d3
	lsr #$02,d3
	cmp.w $ffff96ba.w,d3
	blt .printchars_skipclear
	move.w $ffff96ba.w,d3
	sub.w #$2,d3
	lsl.w #2,d3
	sub d3,$ffff858e.w
.printchars_skipclear:
	move (sp)+,d3
	rts