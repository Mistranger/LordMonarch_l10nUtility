script_text:
	btst #$1,$ffffd1a5.w
	bne .exit
	
	bsr.w .printchars
.exit:
	rts
.printchars_read:
	move.b (a4)+,d3
.printchars_read_new:
	beq .printchars_exit
	cmpi #$7F,d3
	bpl .printchars_read
	cmpi #$15,d3
	bpl .printchars_check_1
	cmpi #$4,d3
	bmi .printchars_check_1
	jmp .printchars_exit
.printchars:
	movem.l d0/d3-d4/d7-a0,-(sp)
	move d0,d3
	; Init variables
	move.w $ffff858a.w,d0 ; $ce8c - x
	move.w $ffffce8e.w,d1 ; $ce8e - y
	move.w $ffffce90.w,d2 ; $ce90 - VRAM address (layer)
.printchars_check_1:
	cmpi #$1,d3
	bne .printchars_check_2
	bsr breakline
	move.w $ffff858a.w,d0 ; $ce8c - x
	move.w $ffffce8e.w,d1 ; $ce8e - y
	bra.w .printchars_read
.printchars_check_2:
	cmpi #$2,d3
	bne .printchars_check_3
	tst $ffffce9c.w
	beq .printchars_read
	bsr printchars_finish_line  ; finish line
	move.l #-$5934,$ffffa6c8.W
	bsr cleanletter_start
	; Re-init variables
	move.w $ffffce84.w,d0 ; $ce84 - x
	move.w $ffffce86.w,d1 ; $ce86 - y
	move.w $ffffce90.w,d2 ; $ce90 - VRAM address (layer)
	lsl.w #3,d0
	move.w d0,$ffff858a.w
	; Call wait & window redraw
	jsr $fff4.l
	clr.w $ffffce9c.W
	clr.w $ffff858c.w
	clr.w $ffff858e.w
	btst #$1,$ffffd1a5.w
	bne .printchars_exit
	bra.w .printchars_read
.printchars_check_3:
	cmpi #$3,d3
	bne .printchars_write
	jsr $010020.l
	bra.w .printchars_read
.printchars_write:
	subi.b #$20,d3
	bsr vwftiles ; vwftiles
	addi.w #$101,$ffffce9c.w
	cmpi.b #$4,($ffffce9d).w
	bcs.b .printchars_nodelay
	movem.l d0-d7/a0-a6,-(sp)
	lea $10c48.l,a0
	jsr $200
	clr.b ($ffffce9d).w
	movem.l (sp)+,d0-d7/a0-a6
.printchars_nodelay:
	jsr $b38.w
	bra.w .printchars_read
.printchars_exit:
	move.w d0,$ffff858a.w
	;move.w $ffffce84.w,$ffffce8c.w
	move.b -(a4),d3
	movem.l (sp)+,d0/d3-d4/d7-a0
    rts