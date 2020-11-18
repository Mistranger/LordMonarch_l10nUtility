printstring_submenu:
	movem.l    a2/a1,-(sp)
	bsr printstring
	movem.l (sp)+,a2/a1
	rts
