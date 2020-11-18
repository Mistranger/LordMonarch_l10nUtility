printstring_struct:	
	movea.l ($1e,a6),a0
	movem.w ($22,a6),d0-d3/d7
	jsr printstring
	clr.l (a6)
	rts
