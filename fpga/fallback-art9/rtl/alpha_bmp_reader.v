// Positive-height 24-bit BI_RGB BMP, 54-byte header. Nearest-neighbour load
// scaling preserves aspect into a640x480 RGB565 frame, padded in hardware.
module alpha_bmp_reader(input clk,rst,start,input[31:0]lba,file_bytes,expected_crc,
 input[20:0]destination_base,output reg done,ok,output reg[3:0]error,output busy,
 input initialized,card_busy,card_done,card_valid,input[7:0]card_data,input[3:0]card_error,
 output reg card_start,output[31:0]card_lba,card_blocks,output card_ready,
 output reg wr_req_toggle,output[20:0]wr_base,output[19:0]wr_len,input wr_ack_toggle,wr_done_toggle,
 output reg[31:0]wr_data,output reg wr_valid,input wr_ready);
 localparam IDLE=0,ALLOC=1,CARD=2,HEADER=3,DIV=4,SETUP=5,ROW=6,PADROW=7,
 LOOK=8,LATCH=9,SEND=10,XADV=11,YADV=12,DRAIN=13,FINISH=14,ZERO=15,PREP=16,GEOM=17;
 reg row_above,row_end,row_next,row_last;reg[4:0]state;reg[21:0]wx,hy;reg[31:0]pos,crc;reg[15:0]w,h;reg[9:0]fw;reg[8:0]fh;reg[10:0]px,srcy,sx,wanty;reg[11:0]xerr,yerr;reg[9:0]dx,dy;
 reg[9:0]left,bottom;reg[1:0]phase,padleft;reg[7:0]blue,green;reg[15:0]first;reg half;
 reg[19:0]sent;reg bad,card_finished;reg[31:0]numer,quot;reg[16:0]rem;reg[15:0]denom;reg[5:0]divstep;reg wide;
 reg crc_pending;reg[7:0]crc_data;
 (* async_reg="true" *)reg[2:0]ack,finished;
 wire[15:0]pixel={card_data[7:3],green[7:2],blue[7:3]};wire[15:0]line_q;
 wire putline=state==ROW&&card_valid&&phase==2;
 bb3_sdp_ram #(.WIDTH(16),.AW(11),.DEPTH(2048),.IMPLEMENT("32K")) rowbuf(clk,putline,px[10:0],pixel,1'b1,sx[10:0],line_q);
 assign busy=state!=IDLE;assign wr_base=destination_base;assign wr_len=153600;
 assign card_lba=lba;assign card_blocks=(file_bytes+511)>>9;
 assign card_ready=state==HEADER||state==ROW||(state==PADROW&&padleft!=0)||state==DRAIN||state==ZERO;
 wire background=dy<bottom||dy>=bottom+fh||dx<left||dx>=left+fw;
 wire[15:0]out_pixel=background ? 16'd0:line_q;
 wire[16:0]newrem={rem[15:0],numer[31]};
 function[31:0]crcbyte;input[31:0]c;input[7:0]b;reg[31:0]t;integer j;begin t=c^b;for(j=0;j<8;j=j+1)t=t[0] ? (t>>1)^32'hedb88320:t>>1;crcbyte=t;end endfunction
 always @(posedge clk)begin
  if(rst)begin state<=IDLE;done<=0;ok<=0;error<=0;card_start<=0;wr_req_toggle<=0;wr_data<=0;wr_valid<=0;
   ack<=0;finished<=0;pos<=0;crc<=32'hffffffff;crc_pending<=0;crc_data<=0;w<=0;h<=0;fw<=0;fh<=0;px<=0;srcy<=0;sx<=0;wanty<=0;dx<=0;dy<=0;xerr<=0;yerr<=0;left<=0;bottom<=0;
   phase<=0;padleft<=0;blue<=0;green<=0;first<=0;half<=0;sent<=0;bad<=0;card_finished<=0;numer<=0;quot<=0;rem<=0;denom<=1;divstep<=0;wide<=0;wx<=0;hy<=0;row_above<=0;row_end<=0;row_next<=0;row_last<=0;
  end else begin
   done<=0;card_start<=0;ack<={ack[1:0],wr_ack_toggle};finished<={finished[1:0],wr_done_toggle};
   if(wr_valid&&wr_ready)begin wr_valid<=0;sent<=sent+1'b1;end
   // Separate the 32-bit length comparison from the wide CRC register enable.
   // The one-byte pipeline also sustains consecutive ready/valid transfers.
   crc_pending<=0;
   if(crc_pending)crc<=crcbyte(crc,crc_data);
   if(card_valid&&card_ready)begin crc_pending<=pos<file_bytes;crc_data<=card_data;pos<=pos+1'b1;end
   if(card_done&&busy)begin card_finished<=1;if(card_error!=0)begin bad<=1;error<=card_error;state<=ZERO;end end
   case(state)
    IDLE:if(start)begin
     ok<=0;error<=0;bad<=0;pos<=0;crc<=32'hffffffff;crc_pending<=0;w<=0;h<=0;sent<=0;half<=0;card_finished<=0;wr_valid<=0;phase<=0;
     wr_req_toggle<=~wr_req_toggle;state<=ALLOC;
    end
    ALLOC:if(ack[2]==wr_req_toggle)state<=CARD;
    CARD:if(initialized&&!card_busy)begin card_start<=1;state<=HEADER;end
    HEADER:if(card_valid)begin
     case(pos)
      0:if(card_data!="B")bad<=1;1:if(card_data!="M")bad<=1;
      10:if(card_data!=54)bad<=1;14:if(card_data!=40)bad<=1;
      11,12,13,15,16,17,20,21,24,25,27,29,30,31,32,33:if(card_data!=0)bad<=1;
      18:w[7:0]<=card_data;19:w[15:8]<=card_data;
      22:h[7:0]<=card_data;23:h[15:8]<=card_data;
      26:if(card_data!=1)bad<=1;28:if(card_data!=24)bad<=1;
      default:;
     endcase
     if(pos==53)begin
      if(bad||w==0||h==0||w>1920||h>1920)begin bad<=1;error<=2;state<=ZERO;end
      else begin
       state<=PREP;
      end
     end
    end
    PREP:begin wx<=(w*22'd480);hy<=(h*22'd640);state<=GEOM;end
    GEOM:begin
     wide<=wx>=hy;numer<=wx>=hy ? hy:wx;denom<=wx>=hy ? w:h;
     rem<=0;quot<=0;divstep<=0;state<=DIV;
    end
    DIV:begin
     numer<={numer[30:0],1'b0};quot<={quot[30:0],newrem>=denom};
     rem<=newrem>=denom ? newrem-denom:newrem;divstep<=divstep+1'b1;
     if(divstep==31)begin
      if(wide)begin fw<=640;fh<=({quot[14:0],newrem>=denom}==0) ? 1:{quot[14:0],newrem>=denom};end
      else begin fh<=480;fw<=({quot[14:0],newrem>=denom}==0) ? 1:{quot[14:0],newrem>=denom};end
      state<=SETUP;
     end
    end
    SETUP:begin left<=(640-fw)>>1;bottom<=(480-fh)>>1;dx<=0;dy<=0;px<=0;srcy<=0;wanty<=0;sx<=0;xerr<=0;yerr<=0;phase<=0;state<=((480-fh)>>1)==0 ? ROW:LOOK;end
    ROW:if(card_valid)begin
     if(phase==0)begin blue<=card_data;phase<=1;end
     else if(phase==1)begin green<=card_data;phase<=2;end
     else begin
      phase<=0;
      if(px+1>=w[10:0])begin px<=0;padleft<=(-w*3)&3;state<=PADROW;end else px<=px+1'b1;
     end
    end
    PADROW:begin
     if(padleft==0)begin
      if(srcy==wanty)begin sx<=0;xerr<=0;dx<=0;state<=LOOK;end
      else begin srcy<=srcy+1'b1;state<=ROW;end
     end else if(card_valid)padleft<=padleft-1'b1;
    end
    LOOK:state<=LATCH;
    LATCH:begin row_above<=dy<bottom;row_end<=dy>=bottom+fh-1;row_next<=dy+1==bottom;row_last<=dy==479;state<=SEND;end
    SEND:if(!wr_valid||wr_ready)begin
     half<=~half;if(!half)first<=out_pixel;else begin wr_data<={out_pixel,first};wr_valid<=1;end
     if(dx==639)begin
      dx<=0;sx<=0;xerr<=0;dy<=dy+1'b1;
      if(row_last)state<=DRAIN;
      else if(row_above)state<=row_next ? ROW:LOOK;
      else if(row_end)state<=LOOK;
      else begin yerr<=yerr+h[10:0];state<=YADV;end
     end else begin
      dx<=dx+1'b1;
      if(!background)begin xerr<=xerr+w[10:0];state<=XADV;end else state<=LOOK;
     end
    end
    XADV:if(xerr>=fw)begin xerr<=xerr-fw;sx<=sx+1'b1;end else state<=LOOK;
    YADV:if(yerr>=fh)begin yerr<=yerr-fh;wanty<=wanty+1'b1;end
     else if(wanty==srcy)state<=LOOK;
     else begin srcy<=srcy+1'b1;px<=0;phase<=0;state<=ROW;end
    DRAIN:if(card_finished)state<=FINISH;
    ZERO:begin
     if(sent+(wr_valid&&wr_ready)<153600&&(!wr_valid||wr_ready))begin wr_data<=0;wr_valid<=1;end
     if(sent>=153600&&!wr_valid&&card_finished)state<=FINISH;
    end
    FINISH:if(sent==153600&&!wr_valid&&finished[2]==wr_req_toggle)begin done<=1;ok<=!bad&&~crc==expected_crc;error<=bad ? error:(~crc!=expected_crc ? 4'd3:0);state<=IDLE;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
