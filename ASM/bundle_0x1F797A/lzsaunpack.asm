; Sample reference depack code for lzsa: https://github.com/emmanuel-marty/lzsa
; Currently only supports the standard stream data, using blocks and forwards-decompression.
; Emphasis is on correctness rather than speed/size.

; MIT License
; 
; Copyright (c) 2016 Steven Tattersall
; 
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
; 
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
; 
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.
    
;------------------------------------------------------------------------------
; Depack a single forward-compressed LZSA v2 block.
; a0 = block data
; a1 = output
; a4 = block end
_decode_block_lzsa2:
	movem.l d1-d7/a0-a6,-(sp)
	moveq   #0,d0
	moveq   #0,d1
	moveq   #0,d2
	moveq   #0,d3
	moveq   #0,d4
	moveq   #0,d5
	moveq   #0,d6
	moveq   #0,d0
	move.b	(a0)+,d0
	lsl.w	#8,d0
	move.b	(a0)+,d0
	moveq	#0,d6
	move.w	d0,d6 ; encoded length
	movea.l a0,a4
	movea.l a1,a2
	adda.l  d6,a4

	moveq	#-1,d4				; d4 = last match offset
	moveq	#-1,d3				; d3 = nybble flag (-1 == read again)
	moveq	#0,d0				; ensure top bits are clear
;	============ TOKEN ==============
.loop:	
	; order of data:
	;* token: <XYZ|LL|MMM>
	;* optional extra literal length
	;* literal values
	;* match offset
	;* optional extra encoded match length

	;7 6 5 4 3 2 1 0
	;X Y Z L L M M M
	move.b	(a0)+,d0			; d0 = token byte

	move.w	d0,d1
	; Length is built in d1
	and.w	#%011000,d1			; d1 = literal length * 8
	beq.s	.no_literals
	lsr.w	#3,d1				; d1 = literal length, 0x0-0x3
	cmp.b	#3,d1				; special literal length?
	bne.s	.copylit

;	============ EXTRA LITERAL LENGTH ==============
	bsr	.read_nybble
	add.b	d2,d1				; generate literal length
	cmp.b	#15+3,d1

	;0-14: the value is added to the 3 stored in the token, to compose the final literals length.
	bne.s	.copylit

	; Ignore d2. Extra byte follows.
	move.b	(a0)+,d1			; read new length
	; assume: * 0-237: 18 is added to the value (3 from the token + 15 from the nibble), to compose the final literals length. 
	add.b	#18,d1				; assume 0-237
	bcc.s	.copylit

	;* 239: a second and third byte follow, forming a little-endian 16-bit value.
	move.b	(a0)+,d7
	move.b	(a0)+,d1
	lsl.w	#8,d1
	or.b   d7,d1


;	============ LITERAL VALUES ==============
.copylit:
	subq.w	#1,d1
.copy_loop:
	move.b	(a0)+,(a1)+
	dbf	d1,.copy_loop

.no_literals:
	cmp.l	a0,a4				; end of block?
	bne.s	.getmatchoff
	move.l  a1,d0
	sub.l   a2,d0
	movem.l (sp)+,d1-d7/a0-a6
	rts

;	============ MATCH OFFSET ==============
.getmatchoff:
;The match offset is decoded according to the XYZ bits in the token
;After all this, d0 is shifted up by 3 bits
	move.w	d0,d1
	moveq	#-1,d2				; offset is "naturally" negative
	add.b	d1,d1				; read top bit
	bcs.s	.matchbits_1
.matchbits_0:
	; top bit 0
	add.b	d1,d1				; read top bit
	bcs.s	.matchbits_01

	;00Z 5-bit offset: read a nibble for offset bits 1-4 and use the inverted bit Z of the token as bit 0 of the offset. set bits 5-15 of the offset to 1.
	bsr	.read_nybble			;d2 = nybble
	eor.b	#$80,d1				;read reverse of "Z" bit into carry
	add.b	d1,d1				;reversed bit put in X flag
	addx.b	d2,d2				;shift up and combine carry
	or.b	#%11100000,d2			;ensure top bits are set again
	bra.s	.matchoffdone
.matchbits_01:
	;01Z 9-bit offset: read a byte for offset bits 0-7 and use the inverted bit Z for bit 8 of the offset.
	;set bits 9-15 of the offset to 1.
	add.w	d1,d1				;read reverse of "Z" bit into carry
	clr.b	d1
	eor.w	d1,d2				;flip bit 8 if needed
	move.b	(a0)+,d2			;offset bits 0-7
	bra.s	.matchoffdone

.matchbits_1:
	add.b	d1,d1				; read top bit
	bcs.s	.matchbits_11

	;10Z 13-bit offset: read a nibble for offset bits 9-12 and use the inverted bit Z for bit 8 of the offset, 
	;then read a byte for offset bits 0-7. set bits 13-15 of the offset to 1.
	bsr.s	.read_nybble
	eor.b	#$80,d1				;read reverse of "Z" bit into carry
	add.b	d1,d1				;reversed bit put in X flag
	addx.b	d2,d2				;shift up and combine carry
	or.b	#%11100000,d2			;ensure top bits are set again
	lsl.w	#8,d2				;move [0:4] up to [12:8]
	move.b	(a0)+,d2			;read bits 0-7
	sub.w	#$200,d2			;undocumented offset -- add 512 byte offset
	bra.s	.matchoffdone

.matchbits_11:
	add.b	d1,d1				; read top bit
	bcs.s	.matchbits111
	;110 16-bit offset: read a byte for offset bits 8-15, then another byte for offset bits 0-7.
	;CAUTION This is big-endian!
	move.b	(a0)+,d2			; low part
	lsl.w	#8,d2
	move.b	(a0)+,d2			; high part
	bra.s	.matchoffdone

.matchbits111:
	;111 repeat offset: reuse the offset value of the previous match command.
	move.l	d4,d2

.matchoffdone:
	move.l	d2,d4				; d4 = previous match
	lea	(a1,d2.l),a3			; a3 = match source (d2.w already negative)

;	============ MATCH LENGTH EXTRA ==============
	; Match Length
	move.w	d0,d1				; clear top bits of length
	and.w	#%00000111,d1			; d1 = match length 0-7
	addq.w	#2,d1				; d1 = match length 2-9
	cmp.w	#2+7,d1
	bne.s	.matchlendone

	; read nybble and add
	bsr	.read_nybble
	;* 0-14: the value is added to the 7 stored in the token, and then the minmatch 
	; of 2 is added, to compose the final match length.
	add.b	d2,d1
	cmp.b	#2+7+15,d1
	bne.s	.matchlendone
	;* 15: an extra byte follows
	;If an extra byte follows here, it can have two possible types of value:
	;* 0-231: 24 is added to the value (7 from the token + 15 from the nibble + minmatch of 2), 
	;to compose the final match length.
	add.b	(a0)+,d1
	bcc.s	.matchlendone

	;* 233: a second and third byte follow, forming a little-endian 16-bit value.
	;*The final encoded match length is that 16-bit value.
	move.b	(a0)+,d7
	move.b	(a0)+,d1
	lsl.w	#8,d1
	or.b    d7,d1

.matchlendone:
.copy_match:
	subq.w	#1,d1				; -1 for dbf
	; " the encoded match length is the actual match length offset by the minimum, which is 3 bytes"
.copym_loop:
	move.b	(a3)+,(a1)+
	dbf	d1,.copym_loop
	bra	.loop

; returns next nibble in d2
; nybble status in d3; top bit set means "read next byte"
.read_nybble:
	tst.b	d3				; anything in the buffer?
	bmi.s	.next_byte
	move.b	d3,d2				; copy buffer contents
	moveq	#-1,d3				; flag buffer is empty
	rts
.next_byte:
	; buffer is empty, so prime next
	move.b	(a0)+,d3			; fetch
	move.b	d3,d2
	lsr.b	#4,d2				; d1 = top 4 bits shifted down (result)
	and.b	#$f,d3				; d3 = remaining bottom 4 bits, with "empty" flag cleared
	rts
