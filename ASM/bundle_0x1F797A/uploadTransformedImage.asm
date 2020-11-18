; everything is same except for part that VWF tiles are split apart in VRAM, so we need to do transform operation on both halves
transformAdvanceNextMission:
	moveq      #$0,D0
	moveq      #$0,D1
	moveq      #$16,D7
.loop:
	; transform upper tiles
	lea        ($00ff1050).l,a0                 

	addi.w     #$100,d0
	jsr        $1b20.w                     
	subi.w     #$100,d0
	jsr        $1ada.w 
	; transform lower tiles
	lea        ($00ff1850).l,a0
	addi.w     #$100,d0
	jsr        $1b20.w                     
	subi.w     #$100,d0
	jsr        $1ada.w 
	addi.w     #$17,d0
	cmpi.w     #$100,d0
	bcs.b      .loop
	subi.w     #$100,d0
	btst.l     #0,d1
	beq.b      .next
	bsr.b      uploadTransformedImage             
	lea        ($010c48).l,a0

	jsr        $0200.w                
.next                                  
	addq.w     #$1,d1
	cmpi.w     #$8,d1
	bcs.b      .loop
	moveq      #$0,d1
	dbf        d7,.loop
	bsr.b      uploadTransformedImage             
	subq.l     #$4,($ffff800a).w             
	rts

uploadTransformedImage:
	movea.l    ($ffff85a4).w,a0                      
	move.w     #$0cf8,(a0)+
	move.w     ($fffff312).w,(a0)+               
	move.l     #$00ff1050,(a0)+                      
	move.w     #$400,(a0)+
	move.w     #$0cf8,(a0)+
	move.w     ($fffff312).w,(a0)
	addi       #$D80,(a0)+          
	move.l     #$00ff1850,(a0)+                      
	move.w     #$400,(a0)+
	move.l     a0,($ffff85a4).w                      
	rts

sym_runPostBattleSaveNameTransform_2:
	move.w     #$0bb2,(a0)+
	move.w     ($fffff312).w,(a0)+ 
    move.l     #$ff1050,(a0)+       
	move.w     #$800,(a0)+
	move.w     #$0bb2,(a0)+
	move.w     ($fffff312).w,(a0)
	addi       #$D80,(a0)+   
    move.l     #$ff1850,(a0)+       
	move.w     #$800,(a0)+
	jmp        $1be8e.l
