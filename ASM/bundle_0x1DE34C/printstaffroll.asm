print_staffroll:
	movem.l a0-a6/d0-d7,-(sp)
    movea.l    ($1e,a6),a0
    move.w     ($22,a6),d2
    move.w     ($14,a6),d0
    move.w     ($18,a6),d1
    move.l #-$5934,$ffffa6c8.W
    bsr cleanletter_start
.nextletter:
	moveq #$0,d3
	move.b (a0)+,d3
	beq .exit2
.printletter:
	subi.b #$20,d3
	bsr vwftiles
	addi.w #$101,$ffffce9c.w
	jsr $b38.w
	bra.w .nextletter
.exit2:
	bsr printchars_finish_line  ; finish line
	move.l     a0,($1e,a6)
	move.w     d0,($14,a6)
	clr.l (a6)
	movem.l (sp)+,a0-a6/d0-d7
	rts