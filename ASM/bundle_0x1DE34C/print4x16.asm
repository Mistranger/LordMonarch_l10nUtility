print4x16:
font8x16 = $166840
startWrite = $FFFFF560
	movem.l    d0-d6/a0-a3,-(sp)                                                                  
    move.w     #$0ccc,d1
    swap       d1
    move.w     d0,d1
	moveq      #$20,d2
	jsr        $0b38.w
	moveq      #$0,d5
.printLoop:
    moveq      #$0,d0
	moveq      #$0,d3
    move.b     (a0)+,d0
    cmpi.b     #$FF,d0
    beq.b      .return
	sub.b      #$20,d0
	move.b     (a0)+,d3
    cmpi.b     #$FF,d3
    bne.b      .start_load
	move.b     #$20,d3
	move.b     #$1,d5
.start_load:
	sub.b      #$20,d3
	; load a couple of letters to RAM and form a tile
	lea        startWrite,a2   
	bsr.b      loadhalf
	lea        startWrite,a2   
	adda.l     #2,a2
	move.l     d3,d0
	bsr.b      loadhalf

	lea        startWrite,a2   
	movea.l    ($ffff85a4).w,a1   
    move.l     d1,(a1)+
    move.l     a2,(a1)+  
	add.w      d2,d1
    adda.w     d2,a2
	move.l     d1,(a1)+
    move.l     a2,(a1)+
	add.w      d2,d1
	move.l     a1,($ffff85a4).w  
	jsr        $0b38.w
.nodraw
	cmpi       #$1,d5
	beq        .return
    bra.b      .printLoop
.return: 	
    movem.l    (sp)+,d0-d6/a0-a3
    rts

loadhalf:
	lea        font8x16,a3   
	lsr.w      #$1,d0
	bcc        .even
	adda.l     #2,a3
.even	
	lsl.w      #$6,d0
	adda.l     d0,a3
	move       #$0f,d6
.copy_loop:
	move.w     (a3)+,(a2)+
	adda.l     #2,a3
	adda.l     #2,a2
	dbf        d6,.copy_loop
	rts	
