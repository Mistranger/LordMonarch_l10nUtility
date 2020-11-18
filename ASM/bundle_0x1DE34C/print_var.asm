print_var:
    movem.l d3/d7/a3,-(sp)
    moveq      #$0,d7
    move.b     (a0)+,d7
    subq.w     #$1,d7
    move.b     (a0)+,d3
    lsl.w      #$8,d3
    move.b     (a0)+,d3
    swap       d3
    move.b     (a0)+,d3
    lsl.w      #$8,d3
    move.b     (a0)+,d3
    movea.l    d3,a3
    moveq      #$0,d3
.var_get:
    lsl.l      #$8,d3
    move.b     (a3)+,d3
    dbf        d7,.var_get
    bsr.w      .var_print  
    movem.l (sp)+,d3/d7/a3
    rts

.var_print:
    move.l     d7,-(sp)
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
    jsr        (a1)
    dbf        d7,.print3

    move.l     (sp)+,d7
    rts