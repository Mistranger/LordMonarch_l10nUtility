menuelement:
	movem.l    d0/a0-a1,-(sp)
	move.w     $ffffce84.w,d0
	lsl.w      #3,d0
	move.w     d0,$ffff858a.w
	lea        ($ffffce84).w,a0
	move.w     ($ffffd18e).w,d0
	lsl.w      #$2,d0
	lea        ($ffffd190).w,a1                             
	move.l     ($8,a0),($0,a1,d0*1)
	addq.w     #$1,($ffffd18e).w  
	movem.l    (sp)+,d0/a0-a1
	rts