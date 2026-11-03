// HXTF v1, stop-and-wait, CRC32/ISO-HDLC. Independent maintenance image only.
module tf_bridge_core #(
 parameter CLK_HZ=50000000, parameter BAUD=1000000,
 parameter FRAME_TIMEOUT=25000000, parameter ARM_TIMEOUT=500000000
)(
 input wire clk,input wire rst,input wire [7:0] rx_data,input wire rx_valid,
 output wire [7:0] tx_data,output wire tx_valid,input wire tx_ready,
 output reg sd_start,output reg sd_write,output reg [31:0] sd_lba,
 input wire sd_initialized,input wire sd_busy,input wire sd_done,input wire [3:0] sd_error,
 input wire [127:0] cid,input wire [127:0] csd,input wire [63:0] sectors,
 input wire [7:0] sd_data,input wire sd_valid,
 input wire [8:0] sd_write_addr,output wire [7:0] sd_write_data,
 output wire sd_reset,output reg armed,output wire active,
 output reg [31:0] discarded_bytes,input wire [31:0] sd_debug1,input wire [31:0] sd_debug2
);
 function [31:0] crc_byte;
 input [31:0] c;input [7:0] b;integer k;reg [31:0] x;
 begin x=c^{24'b0,b};for(k=0;k<8;k=k+1)x=(x>>1)^(x[0]?32'hedb88320:0);crc_byte=x;end
 endfunction
 reg [7:0] header[0:15];
 reg [7:0] payload[0:511];
 reg [7:0] small_payload[0:19];
 reg [7:0] reply[0:575];
 wire [8:0] payload_ra=(state==WAIT_SD && sd_write)?sd_write_addr:copy_n[8:0];
 wire [7:0] payload_rd=payload[payload_ra];
 assign sd_write_data=payload_rd;
 reg [1:0] parser;
 reg [2:0] magic_n;
 reg [9:0] rx_pos,rx_length;
 reg [1:0] crc_n;
 reg [31:0] running_crc,received_crc,idle_ticks;
 reg [7:0] command;
 reg [31:0] seq,lba,request_crc;
 reg [9:0] length;
 reg [3:0] state;
 reg [9:0] copy_n,copy_len,tx_pos,total_len,crc_pos,pad_pos;
 reg [31:0] out_crc;
 reg [7:0] reply_status;
 reg [9:0] reply_payload_length;
 reg reply_we;reg [9:0] reply_wa;reg [7:0] reply_wd;
 wire [7:0] reply_rd=reply[state==SEND?tx_pos:crc_pos];
 reg [31:0] arm_start,arm_count;
 reg [63:0] arm_end;
 reg [31:0] arm_idle;
 reg [3:0] reset_ticks;
 assign sd_reset=reset_ticks!=0;
 localparam IDLE=0,DISPATCH=1,WAIT_SD=2,COPY=3,CRC=4,SEND=5,ARM_CHECK=6,PAD=7,HEADER=8,INFO_BUILD=9,APPEND=10;
 assign active=state!=IDLE;
 assign tx_valid=state==SEND;
 assign tx_data=reply_rd;
 reg last_valid,cache_this;
 reg [31:0] last_seq,last_lba,last_crc;
 reg [7:0] last_cmd;
 reg [9:0] last_length,last_total;
 reg [4:0] cid_pos;
 reg cid_bad;
 reg [9:0] sd_count;
 wire [31:0] incoming_count={small_payload[3],small_payload[2],small_payload[1],small_payload[0]};
 task respond;
 input [7:0] status;input [9:0] body_length;
 reg [9:0] n,rounded;
 begin
   // Full 64-byte reply packets avoid relying on USB-UART short-packet latency.
   rounded=((body_length+21+63)>>6)<<6;n=rounded-20;
   reply_status<=status;reply_payload_length<=n;
   total_len<=rounded;pad_pos<=17+body_length;crc_pos<=4;out_crc<=32'hffffffff;copy_n<=0;state<=HEADER;
 end
 endtask
 // One physical write port per buffer. Header/info/CRC are serialized.
 always @* begin
  reply_we=0;reply_wa=0;reply_wd=0;
  case(state)
   HEADER:begin
    reply_we=1;reply_wa=copy_n;
    case(copy_n)
     0:reply_wd=8'h48;1:reply_wd=8'h58;2:reply_wd=8'h54;3:reply_wd=8'h46;
     4:reply_wd=1;5:reply_wd=command|128;
     6:reply_wd=seq[7:0];7:reply_wd=seq[15:8];8:reply_wd=seq[23:16];9:reply_wd=seq[31:24];
     10:reply_wd=lba[7:0];11:reply_wd=lba[15:8];12:reply_wd=lba[23:16];13:reply_wd=lba[31:24];
     14:reply_wd=reply_payload_length[7:0];15:reply_wd={6'b0,reply_payload_length[9:8]};16:reply_wd=reply_status;
     default:reply_wd=0;
    endcase
   end
   INFO_BUILD:begin
    reply_we=1;reply_wa=17+copy_n;
    case(copy_n)
     0:reply_wd=8'h54;1:reply_wd=8'h46;2:reply_wd=8'h4d;3:reply_wd=8'h31;
     4:reply_wd={5'b0,sd_busy,armed,sd_initialized};5:reply_wd={4'b0,sd_error};
     46:reply_wd=BAUD%256;47:reply_wd=(BAUD>>8)%256;48:reply_wd=(BAUD>>16)%256;49:reply_wd=(BAUD>>24)%256;
     default:begin
      if(copy_n>=6 && copy_n<22)reply_wd=cid[127-(copy_n-6)*8-:8];
      else if(copy_n>=22 && copy_n<38)reply_wd=csd[127-(copy_n-22)*8-:8];
      else if(copy_n>=38 && copy_n<46)reply_wd=sectors[(copy_n-38)*8+:8];
      else if(copy_n>=50 && copy_n<54)reply_wd=sd_debug1[(copy_n-50)*8+:8];
      else if(copy_n>=54 && copy_n<58)reply_wd=sd_debug2[(copy_n-54)*8+:8];
     end
    endcase
   end
   COPY:begin reply_we=1;reply_wa=17+copy_n;reply_wd=payload_rd;end
   PAD:if(pad_pos<total_len-4)begin reply_we=1;reply_wa=pad_pos;reply_wd=0;end
   APPEND:begin reply_we=1;reply_wa=total_len-4+copy_n;reply_wd=~(out_crc>>(copy_n*8));end
   WAIT_SD:if(sd_done && sd_error!=0)begin reply_we=1;reply_wa=17;reply_wd={4'b0,sd_error};end
   default:begin end
  endcase
 end
 always @(posedge clk)begin
  if(reply_we)reply[reply_wa]<=reply_wd;
  if(sd_valid && state==WAIT_SD && !sd_write)payload[sd_count[8:0]]<=sd_data;
  else if(!active && rx_valid && parser==2)payload[rx_pos[8:0]]<=rx_data;
 end
 always @(posedge clk)begin
  if(rst)begin
   parser<=0;magic_n<=0;rx_pos<=0;rx_length<=0;crc_n<=0;running_crc<=32'hffffffff;
   received_crc<=0;idle_ticks<=0;command<=0;seq<=0;lba<=0;request_crc<=0;length<=0;
   state<=IDLE;copy_n<=0;copy_len<=0;tx_pos<=0;total_len<=0;crc_pos<=0;pad_pos<=0;out_crc<=0;reply_status<=0;reply_payload_length<=0;
   sd_start<=0;sd_write<=0;sd_lba<=0;sd_count<=0;reset_ticks<=0;
   armed<=0;arm_start<=0;arm_count<=0;arm_end<=0;arm_idle<=0;discarded_bytes<=0;
   last_valid<=0;cache_this<=0;last_seq<=0;last_lba<=0;last_crc<=0;last_cmd<=0;
   last_length<=0;last_total<=0;cid_pos<=0;cid_bad<=0;
  end else begin
   sd_start<=0;
   if(reset_ticks!=0)reset_ticks<=reset_ticks-1'b1;
   if(armed)begin
    if(arm_idle>=ARM_TIMEOUT)begin armed<=0;arm_idle<=0;end else arm_idle<=arm_idle+1'b1;
   end
   if(sd_valid && state==WAIT_SD && !sd_write)begin
    if(sd_count<512)sd_count<=sd_count+1'b1;
   end
   if(active && rx_valid)discarded_bytes<=discarded_bytes+1'b1;
   if(!active)begin
    if((parser!=0 || magic_n!=0) && !rx_valid)begin
     if(idle_ticks>=FRAME_TIMEOUT)begin parser<=0;magic_n<=0;idle_ticks<=0;end
     else idle_ticks<=idle_ticks+1'b1;
    end
    if(rx_valid)begin
     idle_ticks<=0;
     case(parser)
      0:case(magic_n)
        0:if(rx_data==8'h48)magic_n<=1;
        1:if(rx_data==8'h58)magic_n<=2;else magic_n<=rx_data==8'h48 ? 1:0;
        2:if(rx_data==8'h54)magic_n<=3;else magic_n<=rx_data==8'h48 ? 1:0;
        3:if(rx_data==8'h46)begin parser<=1;rx_pos<=4;running_crc<=32'hffffffff;magic_n<=0;end
          else magic_n<=rx_data==8'h48 ? 1:0;
        default:magic_n<=0;
      endcase
      1:begin
       header[rx_pos[3:0]]<=rx_data;running_crc<=crc_byte(running_crc,rx_data);
       if(rx_pos==15)begin
        if(rx_data>2 || {rx_data,header[14]}>512)begin parser<=0;magic_n<=0;end
        else begin rx_length<={rx_data[1:0],header[14]};rx_pos<=0;crc_n<=0;received_crc<=0;parser<=({rx_data,header[14]}==0)?3:2;end
       end else rx_pos<=rx_pos+1'b1;
      end
      2:begin
       if(rx_pos<20)small_payload[rx_pos[4:0]]<=rx_data;
       running_crc<=crc_byte(running_crc,rx_data);
       if(rx_pos+1==rx_length)begin parser<=3;crc_n<=0;end else rx_pos<=rx_pos+1'b1;
      end
      3:begin
       received_crc[crc_n*8+:8]<=rx_data;
       if(crc_n==3)begin
        command<=header[5];seq<={header[9],header[8],header[7],header[6]};lba<={header[13],header[12],header[11],header[10]};
        length<=rx_length;request_crc<={rx_data,received_crc[23:0]};parser<=0;magic_n<=0;
        state<=DISPATCH;cache_this<=1;arm_idle<=0;
       end else crc_n<=crc_n+1'b1;
      end
     endcase
    end
   end
   case(state)
    DISPATCH:begin
     if(request_crc!=~running_crc)begin cache_this<=0;last_valid<=0;respond(1,0);end
     else if(header[4]!=1)respond(2,0);
     else if(last_valid && seq==last_seq)begin
      cache_this<=0;
      if(command==last_cmd && lba==last_lba && length==last_length && request_crc==last_crc)begin total_len<=last_total;tx_pos<=0;state<=SEND;end
      else begin last_valid<=0;respond(7,0);end
     end else case(command)
      1:if(length!=0)respond(3,0);else begin
       copy_n<=0;state<=INFO_BUILD;
      end
      2,3:begin
       if((command==2 && length!=0)||(command==3 && length!=512))respond(3,0);
       else if(!sd_initialized || sd_busy)respond(4,0);
       else if({32'b0,lba}>=sectors)respond(5,0);
       else if(command==3 && (!armed || lba<arm_start || {32'b0,lba}>=arm_end || csd[13] || csd[12]))respond(6,0);
       else begin sd_write<=command==3;sd_lba<=lba;sd_count<=0;sd_start<=1;state<=WAIT_SD;end
      end
      4:begin
       armed<=0;
       if(length!=20)respond(3,0);
       else if(!sd_initialized || sd_busy)respond(4,0);
       else if(incoming_count==0 || {32'b0,lba}+{32'b0,incoming_count}>sectors)respond(5,0);
       else if(csd[13] || csd[12])respond(6,0);
       else begin cid_pos<=0;cid_bad<=0;state<=ARM_CHECK;end
      end
      5:if(length!=0)respond(3,0);else begin armed<=0;respond(0,0);end
      6:begin copy_n<=0;copy_len<=length;if(length==0)respond(0,0);else state<=COPY;end
      7:if(length!=0)respond(3,0);else begin armed<=0;reset_ticks<=8;respond(0,0);end
      default:respond(2,0);
     endcase
    end
    ARM_CHECK:begin
     if(small_payload[4+cid_pos]!=cid[127-cid_pos*8-:8])cid_bad<=1;
     if(cid_pos==15)begin
      if(cid_bad || small_payload[19]!=cid[7:0])respond(6,0);
      else begin armed<=1;arm_start<=lba;arm_count<=incoming_count;arm_end<={32'b0,lba}+{32'b0,incoming_count};respond(0,0);end
     end else cid_pos<=cid_pos+1'b1;
    end
    WAIT_SD:if(sd_done)begin
     if(sd_error!=0)begin armed<=0;respond(8,1);end
     else if(sd_write)respond(0,0);
     else if(sd_count!=512)respond(9,0);
     else begin copy_n<=0;copy_len<=512;state<=COPY;end
    end
    COPY:begin
     if(copy_n+1==copy_len)respond(0,copy_len);else copy_n<=copy_n+1'b1;
    end
    HEADER:if(copy_n==16)state<=PAD;else copy_n<=copy_n+1'b1;
    INFO_BUILD:if(copy_n==57)respond(0,58);else copy_n<=copy_n+1'b1;
    PAD:if(pad_pos<total_len-4)pad_pos<=pad_pos+1'b1;else state<=CRC;
    CRC:begin
     if(crc_pos<total_len-4)begin out_crc<=crc_byte(out_crc,reply_rd);crc_pos<=crc_pos+1'b1;end
     else begin
      copy_n<=0;state<=APPEND;
     end
    end
    APPEND:if(copy_n==3)begin
      if(cache_this)begin last_valid<=1;last_seq<=seq;last_cmd<=command;last_lba<=lba;last_length<=length;last_crc<=request_crc;last_total<=total_len;end
      tx_pos<=0;state<=SEND;
    end else copy_n<=copy_n+1'b1;
    SEND:if(tx_ready)begin
     if(tx_pos+1==total_len)begin state<=IDLE;parser<=0;magic_n<=0;idle_ticks<=0;end
     else tx_pos<=tx_pos+1'b1;
    end
    default:begin end
   endcase
  end
 end
endmodule
