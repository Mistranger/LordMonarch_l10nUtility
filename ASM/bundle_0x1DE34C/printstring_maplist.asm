printstring_maplist:
	movem.l a0-a2/d0-d7,-(sp)
	move.w d0,$ffffce8c.w ; $ce84 - x
	move.w d1,$ffffce8e.w ; $ce86 - y
	move.w d2,$ffffce90.w ; $ce90 - VRAM address (layer)
	move.w d3,d5
	move.w $ffff96bc.w,d6
	lsl.w #3,d6
	move.w d6,$ffff858e.w
.no_next:
	clr.w $ffffce9c.W
	clr.w $ffff858c.w
	lsl.w #3,d0	
	moveq #$0,d3
.nextletter:
	move.b (a0)+,d3
	beq .exit2
.printletter:
	subi.b #$20,d3
	bsr vwftiles
	addi.w #$101,$ffffce9c.w
	cmpi.b #$4,($ffffce9d).w
	bcs.b .printchars_nodelay
	movem.l d0-d7/a0-a6,-(sp)
	suba.l a0,a0
	jsr $200
	clr.b ($ffffce9d).w
	movem.l (sp)+,d0-d7/a0-a6
	bra.w .nextletter
.printchars_nodelay:
	jsr $b38.w
	bra.w .nextletter
.exit2:
	bsr printchars_finish_line  ; finish line
	move.w $ffff858e.w,d6
	lsr.w #3,d6
	move.w d6,$ffff96bc.w
.exit3:
	movem.l (sp)+,a0-a2/d0-d7
	rts
