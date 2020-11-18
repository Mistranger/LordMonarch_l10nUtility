carriageReturn:
	move.l d0,-(sp)
	; Re-init variables.
	move.w $ffffce84.w,d0 ; $ce84 - x
	lsl.w #3,d0
	move.w d0,$ffff858a.w
	clr.w $ffffce9c.W
	clr.w $ffff858c.w
	move.l #-$5934,$ffffa6c8.W
	bsr cleanletter_start
	move.l (sp)+,d0
	rts
