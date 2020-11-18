runPostBattleSaveNameTransform:
	moveq      #$1c,D1
	addq.w     #$1,($ffffcd3e).w
	move.w     #$20,($ffff96bc).w
	rts