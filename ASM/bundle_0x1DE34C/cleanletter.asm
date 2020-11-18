cleanletter_start:
	movem.l d1-d2/a2,-(sp)
	move.l $ffffa6c8.w,a2
	moveq #$f,d2
.cleanletter_repeat:
	moveq #$0,d1
	move.l d1,(a2)+
	dbf d2,.cleanletter_repeat
	movem.l (sp)+,d1-d2/a2
	rts