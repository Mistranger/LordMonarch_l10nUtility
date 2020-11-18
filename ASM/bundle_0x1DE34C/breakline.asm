breakline:
	move.l d0,-(sp)
	; Re-init variables.
	addi.w #8,$ffff858e.w
	bsr printchars_finish_line_noprint
	move.l #-$5934,$ffffa6c8.W
	bsr cleanletter_start
	; Re-init variables.
	move.w $ffffce84.w,d0 ; $ce84 - x
	lsl.w #3,d0
	addi #$2,$ffffce8e.w
	clr.w $ffffce9c.W
	clr.w $ffff858c.w
	move.w d0,$ffff858a.w
	move.l (sp)+,d0
	rts
