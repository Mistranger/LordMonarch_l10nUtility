op2:	
	movem.l    d0/a0,-(sp)
	lea        ($ffffce84).w,a0
	move.w     #$E6A2,d0
	addq.w     #$1,($4,A0)
	jsr        $0000fe58.l
	subq.w     #$1,($4,A0)
	move.l     ($0,A0),($8,A0)
	clr.w $ffffce9c.W
	clr.w $ffff858c.w
	clr.w $ffff858e.w
	move.w     ($0,A0),d0
	lsl.w      #3,d0
	move.w     d0,$ffff858a.w
	move.l #-$5934,$ffffa6c8.W
	bsr cleanletter_start
	movem.l    (sp)+,d0/a0
	rts
	