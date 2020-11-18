sym_printstring_chapter_title:
printstring_chapter_title:
	movem.l d0-d3/a1-a2,-(sp)
	move.w #$c000,d2
	moveq  #$8,d1
	bsr.w adjust_x
	cmp #1,d3
	beq .two_lines
	bsr.w printstring_map
	movem.l (sp)+,d0-d3/a1-a2
	bra.b .resume
.two_lines:
	bsr.w print_twolines
	movem.l (sp)+,d0-d3/a1-a2
.resume:
	jmp $1d8ae.l
	
sym_printstring_chapter_intermission:
printstring_chapter_intermission:
	movem.l d0-d3/a1-a2,-(sp)
	moveq  #$a,d1
	move.w #$c000,d2
	bsr.w adjust_x
	cmp #1,d3
	beq .two_lines
	bsr.w printstring_map
	movem.l (sp)+,d0-d3/a1-a2
	bra.b .resume
.two_lines:
	bsr.w print_twolines
	movem.l (sp)+,d0-d3/a1-a2
.resume:
	jmp $1db9c.l

sym_printstring_mission_title:
printstring_mission_title:
	movem.l d0-d3/a1-a2,-(sp)
	moveq  #$c,d1
	move.w #$c000,d2
	bsr.w adjust_x
	cmp #1,d3
	beq .two_lines
	bsr.w printstring_map
	movem.l (sp)+,d0-d3/a1-a2
	bra.b .resume
.two_lines:
	bsr.w print_twolines
	movem.l (sp)+,d0-d3/a1-a2
.resume:
	jmp $1da68.l
	
sym_printstring_mission_results:
printstring_mission_results:
	movem.l d0-d3/a1-a2,-(sp)
	moveq  #$4,d1
	move.w #$c000,d2
	bsr.w adjust_x
	cmp #1,d3
	beq .two_lines
	bsr.w printstring_map
	movem.l (sp)+,d0-d3/a1-a2
	bra.b .resume
.two_lines:
	bsr.w print_twolines
	movem.l (sp)+,d0-d3/a1-a2
.resume:
	jmp $1ad7e.l
	
sym_printstring_challenge_ending:
printstring_challenge_ending:
	movem.l d0-d3/a1-a2,-(sp)
	bsr.w adjust_x
	cmp #1,d3
	beq .two_lines
	movem.l a0-a1/d4,-(sp)
	lea ($ffffa87c).w,a1
	bsr.w add_printstring_map_struct
	movem.l (sp)+,a0-a1/d4
	movem.l (sp)+,d0-d3/a1-a2
	bra.b .resume
.two_lines:
	bsr.w print_twolines_struct
	movem.l (sp)+,d0-d3/a1-a2
.resume:
	rts
	
print_twolines:
	subi.w #1,d1
	exg a0,a1 
	bsr.w adjust_x
	bsr.w printstring_map
	exg a0,a1 
	addi.w #2,d1
	exg a0,a2 
	bsr.w adjust_x
	bsr.w printstring_map
	exg a0,a2
	rts
	
print_twolines_struct:
	subi.w #2,d1
	exg a0,a1 
	bsr.w adjust_x
	movem.l a0-a1/d4,-(sp)
	lea ($ffffa87c).w,a1
	bsr.w add_printstring_map_struct
	movem.l (sp)+,a0-a1/d4
	exg a0,a1 
	addi.w #2,d1
	exg a0,a2 
	bsr.w adjust_x
	movem.l a0-a1/d4,-(sp)
	lea ($ffffa8ae).w,a1
	bsr.w add_printstring_map_struct
	movem.l (sp)+,a0-a1/d4
	exg a0,a2
	rts

adjust_x:
	move.l d1,-(sp)
	bsr.w get_pixel_length
	cmpi.w #$C0,d0
	bgt .two_lines
	move.w #$00A0,d1
	lsr.w #1,d0
	sub.w d0,d1
	move.w d1,d0
	move.l (sp)+,d1
	rts
.two_lines:
	movem.l a0/d0,-(sp)
	lea $00ff1000,a2
	move.l #$10,d3
.cleanbuffer:
	move.l #0,(a2)+
	dbf d3,.cleanbuffer
	lea $00ff1000,a2
.copytobuffer:
	move.b (a0)+,d3
	beq .next
	move.b d3,(a2)+
	bra.b .copytobuffer
.next:
	lea $00ff1000,a0
	jsr $1d2c.w  ; strlen
	lsr.w #2,d0
	adda d0,a0
.find_space:
	move.b (a0)+,d3
	cmpi.b #$20,d3
	beq .found
	cmpi.b #$0,d3
	beq .notfound
	bra.b .find_space
.found:
	move.b -(a0),d3
	move.b #0,(a0)+
	move.l a0,d3
	subi.l #$00ff1000,d3
	bra.b .exit
.notfound:
	moveq #0,d3
	movem.l (sp)+,a0/d0
	move.l (sp)+,d1
	rts
.exit:
	lea $00ff1000,a1
	movea.l a1,a2
	adda.l d3,a2
	moveq #1,d3
	movem.l (sp)+,a0/d0
	move.l (sp)+,d1
	rts
	
get_pixel_length:
	movem.l a0/a1/d3,-(sp)
	lea $19adc0,a1
	moveq #0,d0
	moveq #0,d3
.loop
	move.b (a0)+,d3
	beq .exit2
	subi.w #$20,d3
	add.b $00(a1,d3.w),d0
	bra.b .loop
.exit2
	movem.l (sp)+,a0/a1/d3
	rts
	
printstring_map_prepare:
	lea vwftiles,a1
	lea $b38.w,a2
	move.w $ffff96bc.w,d6
	lsl.w #3,d6
	move.w d6,$ffff858e.w
	moveq #0,d6
	move.w d0,d6
	divu #8,d6
	swap d6
	add.w d6,$ffff858e.w
	move.l #-$5934,$ffffa6c8.W
	bsr cleanletter_start
	clr.w $ffffce9c.W
	clr.w $ffff858c.w
	moveq #$0,d3
	rts
	
printstring_map:
	movem.l a0-a2/d0-d7,-(sp)
	bsr.w printstring_map_prepare
.nextletter:
	move.b (a0)+,d3
	beq .exit2
.printletter:
	subi.b #$20,d3
	bsr vwftiles
	addi.w #$101,$ffffce9c.w
	jsr $b38.w
	bra.w .nextletter
.exit2:
	bsr printchars_finish_line  ; finish line
	move.w $ffff858e.w,d6
	lsr.w #3,d6
	move.w d6,$ffff96bc.w
	movem.l (sp)+,a0-a2/d0-d7
	rts

add_printstring_map_struct:	
	exg        A0,A1
	move.l a2,-(sp)
	lea printstring_map_struct,a2
	move.l     a2,(A0)
	move.l (sp)+,a2
	move.l     A1,($1e,A0)
	movem.w    d0-d4,($22,A0)
	rts

printstring_map_struct:	
	movea.l ($1e,a6),a0
	movem.w ($22,a6),d0-d3/d7
	bsr.w printstring_map_prepare
.nextletter:
	move.b (a0)+,d3
	beq .exit2
.printletter:
	subi.b #$20,d3
	bsr vwftiles
	addi.w #$101,$ffffce9c.w
	cmpi.b #$8,($ffffce9d).w
	bcs.b .printchars_nodelay
	movem.l d0-d7/a0-a6,-(sp)
	lea $10c48.l,a0
	jsr $200
	clr.b ($ffffce9d).w
	movem.l (sp)+,d0-d7/a0-a6
	bra.w .nextletter
.printchars_nodelay:
	jsr $b38.w
	bra.w .nextletter
.exit2:
	bsr printchars_finish_line  ; finish line
	move.w $ffff858e.w,d6
	lsr.w #3,d6
	move.w d6,$ffff96bc.w
	clr.l (a6)
	rts
