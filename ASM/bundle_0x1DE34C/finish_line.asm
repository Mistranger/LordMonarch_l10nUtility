printchars_finish_line:
	move.w #$60,d3
	bsr vwftiles  
	jsr $b38.w
printchars_finish_line_noprint:	
	moveq.l #$0,d3
	move.w $ffff858e.w,d3
	divu #$08,d3
	swap d3
	move.w #$8,d0
	sub.w d3,d0
	add.w d0,$ffff858e.w
	rts
	
printchars_finish_line_continue:
	move.w #$60,d3
	bsr vwftiles  
	jsr $b38.w
	moveq.l #$0,d3
	move.w $ffff858e.w,d3
	divu #$08,d3
	swap d3
	move.w #$8,d0
	sub.w d3,d0
	add.w d0,$ffff858e.w
	rts