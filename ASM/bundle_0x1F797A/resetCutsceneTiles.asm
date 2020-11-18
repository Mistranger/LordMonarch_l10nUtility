resetCutsceneTiles:
	clr.w      $ffff858e.w
	move.w     #$d440,d0
	moveq      #$e,d1
	jmp $1eb20.l

