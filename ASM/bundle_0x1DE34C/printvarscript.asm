printvarscript:
    movem.l     d3/d7,-(sp)
	move.l      d0,d3
	move.w $ffff858a.w,d0 ;x
    moveq      #$0,d7
.print1:
    divu.w     #$a,d3
    beq.b      .print2
    swap       d3
    move.w     d3,-(sp)
    clr.w      d3
    swap       d3
    addq.w     #$1,d7
    bra.b      .print1
.print2:              
    swap       d3
    bra.b      .print4
.print3:                            
    move.w     (sp)+,d3
.print4:      
    add		   #$10,d3	
    bsr.w        vwftiles
	jsr $b38.w
    dbf        d7,.print3	
	move.w     d0,$ffff858a.w
	movem.l     (sp)+,d3/d7
    rts
