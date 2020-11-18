resetCacheTile:
	move.w     d4,($ffff96c2).w
	clr.w      $ffff858e.w
	move.l d0,-(sp)
	move.w $ffffce84.w,d0 ; $ce86 - y
	lsl.w #3,d0
	move.w d0,$ffff858a.w
	move.l (sp)+,d0
	rts

