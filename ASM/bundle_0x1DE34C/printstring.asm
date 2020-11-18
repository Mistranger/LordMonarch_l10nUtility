printstring:
	movem.l a0-a2/d0-d7,-(sp)
	lea vwftiles,a1   
	lea $b38.w,a2
	move.w d3,d5
	move.w d0,d4
	move.w $ffff96bc.w,d6
	lsl.w #3,d6
	move.w d6,$ffff858e.w
	move.l #-$5934,$ffffa6c8.W
	bsr cleanletter_start
	clr.w $ffffce9c.W
	clr.w $ffff858c.w
	lsl.w #3,d0
	moveq #$0,d3
.nextletter:
	move.b (a0)+,d3
	beq .exit2
	cmpi.b #$1,d3
	bne .check_printvar
	bsr printchars_finish_line
	move.w d4,d0 
	lsl.w #3,d0
	add d5,d1
	bra.b .nextletter
.check_printvar:
    cmpi.b #$6,d3
    bne.b .check_inlinecode
	bsr print_var
	jsr $b38.w
	bra.b .nextletter
.check_inlinecode:
	cmpi.b #$9,d3
	bne .printletter
	jsr $1ee0.w
	bra.w .nextletter
.printletter:
	subi.b #$20,d3
	bsr vwftiles
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
