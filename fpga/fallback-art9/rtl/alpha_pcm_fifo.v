// 8192x16, four 32K pages. Reset both domains for a track change.
module alpha_pcm_fifo(input wc,wrst,we,input[15:0]din,output full,output[13:0]wcount,
 input rc,rrst,re,output[15:0]dout,output reg valid,output empty,output[13:0]rcount);
 reg[13:0]wb,wg,rb,rg;(* async_reg="true" *)reg[13:0]r1,r2,w1,w2;
 wire wf=we&&!full,rf=re&&!empty;wire[13:0]wn=wb+wf,rn=rb+rf;
 wire[13:0]wgn=(wn>>1)^wn,rgn=(rn>>1)^rn;
 function[13:0]bin;input[13:0]g;integer k;begin bin[13]=g[13];for(k=12;k>=0;k=k-1)bin[k]=bin[k+1]^g[k];end endfunction
 assign full=wg=={~r2[13:12],r2[11:0]};assign empty=rg==w2;
 assign wcount=wb-bin(r2);assign rcount=bin(w2)-rb;
 always @(posedge wc or posedge wrst)if(wrst)begin wb<=0;wg<=0;r1<=0;r2<=0;end else begin wb<=wn;wg<=wgn;r1<=rg;r2<=r1;end
 always @(posedge rc or posedge rrst)if(rrst)begin rb<=0;rg<=0;w1<=0;w2<=0;valid<=0;end else begin rb<=rn;rg<=rgn;w1<=wg;w2<=w1;valid<=rf;end
 `ifdef __ICARUS__
 reg[15:0]mem[0:8191];reg[15:0]q;always @(posedge wc)if(wf)mem[wb[12:0]]<=din;
 always @(posedge rc)if(rf)q<=mem[rb[12:0]];assign dout=q;
 `else
 wire[63:0]q;reg[1:0]bank;always @(posedge rc)if(rf)bank<=rb[12:11];
 genvar n;generate for(n=0;n<4;n=n+1)begin:page
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(16),.DATA_WIDTH_B(16),.ADDR_WIDTH_A(11),.ADDR_WIDTH_B(11),.DATA_DEPTH_A(2048),.DATA_DEPTH_B(2048),.BYTE_ENABLE(0),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("32K")) storage(
 .clka(wc),.cea(1'b1),.wea(wf&&wb[12:11]==n),.rsta(1'b0),.ocea(1'b0),.dia(din),.addra(wb[10:0]),.bea(1'b1),.doa(),
 .clkb(rc),.ceb(rf&&rb[12:11]==n),.web(1'b0),.rstb(1'b0),.oceb(1'b1),.dib(16'd0),.addrb(rb[10:0]),.beb(1'b1),.dob(q[n*16+:16]));end endgenerate
 assign dout=q[bank*16+:16];
 `endif
endmodule
