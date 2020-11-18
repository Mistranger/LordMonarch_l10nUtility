sym_runScript:
runScript:
	clr.w      ($ffffce9c).w
	st         ($ffffce92).w  
	st         ($ffffce96).w
	clr.w      ($ffff858a).w
	move.l #-$5934,$ffffa6c8.W
	bsr cleanletter_start
	move.w $ffffce8c.w,d0 ; $ce8c - x 
	lsl.w #3,d0
	move.w d0,$ffff858a.w ; $ce8c - x 
	
	jmp $ff02.l ; selectOP
	
sym_runScriptEnd:
runScriptEnd:
	move.l d0,-(sp)
	clr.w $ffff858c.w
	clr.w $ffff858e.w
	move.w $ffffce86.w,$ffffce8e.w ; $ce86 - y
	move.w $ffffce84.w,d0 ; $ce86 - y
	lsl.w #3,d0
	move.w d0,$ffff858a.w
	movem.l d0-d7/a0-a6,-(sp)
	lea $10c48.l,a0
	jsr $200
	clr.w ($ffffce9c).w
	movem.l (sp)+,d0-d7/a0-a6
	move.l (sp)+,d0
	jsr $010218.l
	moveq  #$0,d0
	jmp $0ff34.l

	
