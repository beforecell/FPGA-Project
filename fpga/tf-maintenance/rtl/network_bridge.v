// HXTN v1 packet adapter around verified HXTF SD maintenance core.
// Application domain50MHz;vendor MAC/frame FIFOs handle RGMII clock crossing.
module network_bridge #(
 parameter integer SLOTS=16,
 parameter integer WATCHDOG=150000000
)(input wire clk,input wire rst,
 input wire[7:0]rx_data,input wire rx_valid,input wire[15:0]rx_length,
 input wire udp_tx_ready,input wire udp_tx_ack,
 output wire[7:0]tx_data,output wire tx_valid,output wire tx_request,output wire[15:0]tx_length,
 output reg[31:0]local_ip,output reg[31:0]peer_ip,output reg[15:0]peer_port,
 output reg[7:0]core_rx_data,output reg core_rx_valid,
 input wire[7:0]core_tx_data,input wire core_tx_valid,output wire core_tx_ready,
 input wire core_armed,input wire sd_ready,input wire[3:0]sd_error,
 output reg core_fault_reset,output reg[31:0]dropped,output reg[31:0]accepted,
 output wire[4:0]queued);
 function[31:0]crc_byte;
 input[31:0]c;input[7:0]b;integer k;reg[31:0]x;
 begin x=c^b;for(k=0;k<8;k=k+1)x=(x>>1)^(x[0]?32'hedb88320:0);crc_byte=x;end
 endfunction
 reg[7:0]packets[0:16383];
 reg[9:0]lengths[0:15];reg[7:0]kinds[0:15];reg[31:0]cookies[0:15];
 reg[31:0]host_ips[0:15],board_ips[0:15];reg[15:0]host_ports[0:15];
 reg[4:0]wp,rp;
 assign queued=wp-rp;
 reg[15:0]rx_pos,rx_total,rx_payload;
 reg[31:0]rx_crc,rx_magic,rx_cookie,rx_first,rx_board;
 reg[15:0]rx_port,rx_inner_len;
 reg[7:0]rx_kind,rx_version;
 reg rx_drop;
 wire full=queued==16;
 wire last_rx=rx_pos!=0 && rx_pos+1==rx_total;
 wire[31:0]next_crc=crc_byte(rx_pos==0?32'hffffffff:rx_crc,rx_data);
 wire packet_ok=rx_magic==32'h4858544e && rx_version==1 && rx_payload+16==rx_total &&
   next_crc==32'hdebb20e3 && rx_cookie!=0 &&
   ((rx_kind==1 && rx_payload==10) ||
    (rx_kind==3 && rx_payload>=20 && rx_payload<=532 && rx_first==32'h48585446 && rx_payload==rx_inner_len+20));
 wire packet_write=rx_valid && !rx_drop && !full && rx_pos>=12 && rx_pos<rx_total-4 && rx_pos<544;
 wire[9:0]packet_wa=rx_pos-12;
 reg[9:0]feed_n;reg[7:0]packet_q;
 always @(posedge clk)begin
  if(packet_write)packets[{wp[3:0],packet_wa}]<=rx_data;
  packet_q<=packets[{rp[3:0],feed_n}];
 end
 reg[31:0]rx_idle;
 always @(posedge clk)begin
  if(rst)begin
   wp<=0;rx_pos<=0;rx_total<=0;rx_payload<=0;rx_crc<=32'hffffffff;rx_magic<=0;
   rx_cookie<=0;rx_first<=0;rx_board<=0;rx_port<=0;rx_inner_len<=0;rx_kind<=0;rx_version<=0;rx_drop<=0;
   dropped<=0;accepted<=0;rx_idle<=0;
  end else begin
   if(rx_pos!=0 && !rx_valid)begin
    if(rx_idle==5000000)begin rx_pos<=0;rx_idle<=0;dropped<=dropped+1'b1;end
    else rx_idle<=rx_idle+1'b1;
   end
   if(rx_valid)begin
    rx_idle<=0;rx_crc<=next_crc;
    // The vendor UDP core updates its length alongside the first payload
    // bytes. Sample throughout the packet rather than latching stale metadata.
    rx_total<=rx_length;
    if(rx_pos==0)rx_drop<=full;
    if(rx_pos<4)rx_magic<={rx_magic[23:0],rx_data};
    case(rx_pos)
     4:rx_version<=rx_data;5:rx_kind<=rx_data;
     6:rx_payload[7:0]<=rx_data;7:rx_payload[15:8]<=rx_data;
     8:rx_cookie[7:0]<=rx_data;9:rx_cookie[15:8]<=rx_data;10:rx_cookie[23:16]<=rx_data;11:rx_cookie[31:24]<=rx_data;
     12,13,14,15:rx_first<={rx_first[23:0],rx_data};
     16:rx_port[15:8]<=rx_data;17:rx_port[7:0]<=rx_data;
     18,19,20,21:rx_board<={rx_board[23:0],rx_data};
     26:rx_inner_len[7:0]<=rx_data;27:rx_inner_len[15:8]<=rx_data;
     default:begin end
    endcase
    if(last_rx)begin
     rx_pos<=0;
     if(!rx_drop && !full && rx_total>=16 && rx_total<=548 && packet_ok)begin
      lengths[wp[3:0]]<=rx_payload[9:0];kinds[wp[3:0]]<=rx_kind;cookies[wp[3:0]]<=rx_cookie;
      host_ips[wp[3:0]]<=rx_first;host_ports[wp[3:0]]<=rx_port;board_ips[wp[3:0]]<=rx_board;
      wp<=wp+1'b1;accepted<=accepted+1'b1;
     end else dropped<=dropped+1'b1;
    end else rx_pos<=rx_pos+1'b1;
   end
  end
 end
 localparam IDLE=0,FEED_WAIT=1,FEED_SEND=2,WAIT_REPLY=3,HELLO_BUILD=4,PREPARE=5,WAIT_ACK=6,SEND=7;
 reg[3:0]state;
 reg[31:0]session,timer,out_crc;
 reg[9:0]reply_n,reply_len,out_n;reg[15:0]udp_length;
 reg[7:0]reply_kind;
 reg[7:0]reply_ram[0:575];reg[7:0]reply_q;
 wire[9:0]reply_ra=(out_n>=11 && out_n<reply_len+11)?out_n-11:0;
 reg[7:0]hello_byte;
 always @*begin
  hello_byte=0;
  case(reply_n)
   0:hello_byte="N";1:hello_byte="T";2:hello_byte="F";3:hello_byte="1";
   4:hello_byte=local_ip[31:24];5:hello_byte=local_ip[23:16];6:hello_byte=local_ip[15:8];7:hello_byte=local_ip[7:0];
   8:hello_byte=16;9:hello_byte=0;10:hello_byte={2'b0,sd_error,core_armed,sd_ready};11:hello_byte=0;
   12:hello_byte=dropped[7:0];13:hello_byte=dropped[15:8];14:hello_byte=dropped[23:16];15:hello_byte=dropped[31:24];
   default:hello_byte=0;
  endcase
 end
 always @(posedge clk)begin
  if(state==HELLO_BUILD)reply_ram[reply_n]<=hello_byte;
  else if(state==WAIT_REPLY && core_tx_valid)reply_ram[reply_n]<=core_tx_data;
  reply_q<=reply_ram[reply_ra];
 end
 reg[7:0]out_byte;
 always @*begin
  out_byte=0;
  case(out_n)
   0:out_byte="H";1:out_byte="X";2:out_byte="T";3:out_byte="N";4:out_byte=1;5:out_byte=reply_kind;
   6:out_byte=reply_len[7:0];7:out_byte={6'b0,reply_len[9:8]};
   8:out_byte=session[7:0];9:out_byte=session[15:8];10:out_byte=session[23:16];11:out_byte=session[31:24];
   default:if(out_n<reply_len+12)out_byte=reply_q;
    else case(out_n-reply_len-12)
     0:out_byte=~out_crc[7:0];1:out_byte=~out_crc[15:8];2:out_byte=~out_crc[23:16];3:out_byte=~out_crc[31:24];default:out_byte=0;
    endcase
  endcase
 end
 assign tx_data=out_byte;
 assign tx_valid=state==SEND;
 assign tx_request=state==WAIT_ACK;
 // The vendor stack still consumes this metadata after app data has ended.
 // Preparing the next SD reply must not change the previous packet's length.
 assign tx_length=udp_length;
 assign core_tx_ready=state==WAIT_REPLY;
 always @(posedge clk)begin
  if(rst)begin
   state<=IDLE;rp<=0;local_ip<=32'hffffffff;peer_ip<=32'hffffffff;peer_port<=49193;
   session<=0;timer<=0;out_crc<=32'hffffffff;feed_n<=0;reply_n<=0;reply_len<=0;out_n<=0;reply_kind<=0;udp_length<=0;
   core_rx_data<=0;core_rx_valid<=0;core_fault_reset<=0;
  end else begin
   core_rx_valid<=0;core_fault_reset<=0;
   if(state!=IDLE)timer<=timer+1'b1;else timer<=0;
   if(state!=IDLE && timer==WATCHDOG)begin
    state<=IDLE;rp<=rp+1'b1;core_fault_reset<=1;
   end else case(state)
    IDLE:if(wp!=rp)begin
     if(kinds[rp[3:0]]==1)begin
      if((!core_armed || cookies[rp[3:0]]==session) && host_ports[rp[3:0]]>=1024 && host_ips[rp[3:0]]!=0 && board_ips[rp[3:0]]!=host_ips[rp[3:0]])begin
       session<=cookies[rp[3:0]];local_ip<=board_ips[rp[3:0]];peer_ip<=host_ips[rp[3:0]];peer_port<=host_ports[rp[3:0]];
       reply_kind<=8'h81;reply_len<=16;reply_n<=0;state<=HELLO_BUILD;
      end else rp<=rp+1'b1;
     end else if(cookies[rp[3:0]]==session && session!=0)begin feed_n<=0;reply_n<=0;reply_len<=0;reply_kind<=8'h83;state<=FEED_WAIT;end
     else rp<=rp+1'b1;
    end
    FEED_WAIT:state<=FEED_SEND;
    FEED_SEND:begin
     core_rx_data<=packet_q;core_rx_valid<=1;
     if(feed_n+1==lengths[rp[3:0]])begin state<=WAIT_REPLY;reply_n<=0;end
     else begin feed_n<=feed_n+1'b1;state<=FEED_WAIT;end
    end
    WAIT_REPLY:if(core_tx_valid)begin
     if(reply_n==14)reply_len[7:0]<=core_tx_data;
     if(reply_n==15)reply_len<={core_tx_data[1:0],reply_len[7:0]}+20;
     if(reply_len!=0 && reply_n+1==reply_len)begin state<=PREPARE;out_n<=0;out_crc<=32'hffffffff;end
     else reply_n<=reply_n+1'b1;
    end
    HELLO_BUILD:if(reply_n==15)begin state<=PREPARE;timer<=0;out_n<=0;out_crc<=32'hffffffff;end else reply_n<=reply_n+1'b1;
    PREPARE:if(udp_tx_ready)begin udp_length<={6'b0,reply_len}+16;state<=WAIT_ACK;end
    WAIT_ACK:if(udp_tx_ack)begin state<=SEND;out_n<=0;out_crc<=32'hffffffff;end
    SEND:begin
     if(out_n<reply_len+12)out_crc<=crc_byte(out_crc,out_byte);
     if(out_n+1==reply_len+16)begin state<=IDLE;rp<=rp+1'b1;end else out_n<=out_n+1'b1;
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
