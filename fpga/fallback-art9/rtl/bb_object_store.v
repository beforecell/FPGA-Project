// Read raw-sector objects, validate their headers and CRC32, write only an
// unpublished SDRAM slot. A damaged/short transfer is padded to retire the
// write job; it is NEVER marked valid by the replay manager.
module bb_object_store #(parameter CLK_HZ=100000000,VIDEO_ONLY=0)(
 input clk,rst,job_start,input[31:0]asset_base,input [1:0] job_kind,input [15:0] job_index,input [4:0] job_slot,
 output reg job_done,job_ok,output reg [3:0] error,output busy,output [31:0] debug_status,
 output reg header_valid,output reg [15:0] frame_count,nominal_fps,
 output reg [7:0] default_threshold,output reg [31:0] bmp_lba,
 output reg [31:0] crc_actual,crc_expected,timestamp_ms,
 input card_initialized,card_busy,card_done,input [3:0] card_error,
 output reg card_start,output reg [31:0] card_lba,card_blocks,
 input [7:0] card_data,input card_valid,output card_ready,
 output reg wr_req_toggle,output reg [20:0] wr_base,output reg [19:0] wr_len,
 input wr_ack_toggle,wr_done_toggle,output [31:0] wr_data,output wr_valid,input wr_ready
);
 localparam IDLE=0,ALLOCATE=1,WACK=2,CARD=3,RECEIVE=4,PAD=5,FINISH=6,VERIFY=7;
 reg [2:0] state;
 reg [1:0] kind;reg [15:0] index;reg [4:0] slot;
 reg [20:0] pos,total_bytes;reg bad_header,seen_busy;
 (* preserve=1 *)reg invalid_header,invalid_crc;
 reg [31:0] crc,expected,watchdog;
 reg [31:0] bmp_crc[0:3];reg [31:0] bmp_count;
 reg [31:0] pending_word;reg pending;
 reg [19:0] words_sent;
 reg [1:0] byte_phase,bgr_phase;reg [23:0] accumulator;
 reg [7:0] blue,green;reg [15:0] pixel0;reg pixel_half;
 (* async_reg="true" *)reg [2:0] wa_sync,wd_sync;
 wire byte_fire=card_valid&&card_ready;
 wire [15:0] rgb565={card_data[7:3],green[7:2],blue[7:3]};
 assign debug_status={state,kind,header_valid,card_initialized,card_busy,card_error,pos[19:0]};
 assign busy=state!=IDLE;
 assign wr_data=pending_word;assign wr_valid=pending;
 // Accept only into the empty registered staging word. Avoid propagating
 // downstream FIFO-full through ready into every parser/CRC clock enable.
 // Native SD supplies a byte every four control clocks; the optional one-
 // clock release gap fits inside that interval and cannot overwrite a word.
 assign card_ready=state==PAD || (state==RECEIVE && !pending);
 function [31:0] crc32_byte;
  input [31:0] c;input [7:0] b;reg [31:0] t;integer j;
  begin t=c^{24'd0,b};for(j=0;j<8;j=j+1)t=t[0]?(t>>1)^32'hedb88320:t>>1;crc32_byte=t;end
 endfunction
 function [7:0] magic_global;input [2:0] n;
  begin case(n)0:magic_global="H";1:magic_global="X";2:magic_global="B";3:magic_global="B";
   4:magic_global="X";5:magic_global="0";6:magic_global="0";7:magic_global="5";endcase end
 endfunction
 function [7:0] magic_frame;input [2:0] n;
  begin case(n)0:magic_frame="B";1:magic_frame="B";2:magic_frame="F";3:magic_frame="R";
   4:magic_frame="A";5:magic_frame="M";6:magic_frame="E";7:magic_frame="5";endcase end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;kind<=0;index<=0;slot<=0;job_done<=0;job_ok<=0;error<=0;
   header_valid<=0;frame_count<=0;nominal_fps<=30;default_threshold<=24;bmp_lba<=0;bmp_count<=0;
   bmp_crc[0]<=0;bmp_crc[1]<=0;bmp_crc[2]<=0;bmp_crc[3]<=0;
   crc_actual<=0;crc_expected<=0;timestamp_ms<=0;card_start<=0;card_lba<=0;card_blocks<=0;
   wr_req_toggle<=0;wr_base<=0;wr_len<=0;wa_sync<=0;wd_sync<=0;
   pos<=0;total_bytes<=0;bad_header<=0;seen_busy<=0;invalid_header<=0;invalid_crc<=0;crc<=32'hffffffff;expected<=0;watchdog<=0;
   pending_word<=0;pending<=0;words_sent<=0;byte_phase<=0;bgr_phase<=0;accumulator<=0;blue<=0;green<=0;pixel0<=0;pixel_half<=0;
  end else begin
   card_start<=0;job_done<=0;
   wa_sync<={wa_sync[1:0],wr_ack_toggle};wd_sync<={wd_sync[1:0],wr_done_toggle};
   if(state==IDLE || byte_fire || (pending&&wr_ready))watchdog<=0;else watchdog<=watchdog+1'b1;
   if(pending&&wr_ready)begin pending<=0;words_sent<=words_sent+1'b1;end
   case(state)
    IDLE:if(job_start)begin
     kind<=job_kind;index<=job_index;slot<=job_slot;pos<=0;bad_header<=0;seen_busy<=0;
     error<=0;job_ok<=0;crc<=32'hffffffff;expected<=0;timestamp_ms<=0;
     pending<=0;words_sent<=0;byte_phase<=0;bgr_phase<=0;pixel_half<=0;
     if(job_kind==0)begin header_valid<=0;wr_len<=0;card_lba<=asset_base+2337;card_blocks<=1;total_bytes<=512;state<=CARD;end
     else if(job_kind==1&&!VIDEO_ONLY)begin
      wr_base<=job_index[1:0]*21'd153600;wr_len<=153600;
      card_lba<=bmp_lba+job_index*32'd1801;card_blocks<=1801;total_bytes<=1801*512;
      expected<=bmp_crc[job_index[1:0]];state<=ALLOCATE;
     end else begin
      wr_base<=21'd614400+job_slot*21'd57600;wr_len<=57600;
      card_lba<=asset_base+4096+job_index*32'd451;card_blocks<=451;total_bytes<=451*512;state<=ALLOCATE;
     end
    end
    ALLOCATE:begin wr_req_toggle<=~wr_req_toggle;state<=WACK;end
    WACK:if(wa_sync[2]==wr_req_toggle)state<=CARD;
    CARD:if(card_initialized&&!card_busy)begin card_start<=1;seen_busy<=0;state<=RECEIVE;end
    RECEIVE:begin
     if(card_busy)seen_busy<=1;
     if(byte_fire)begin
      pos<=pos+1'b1;
      if(kind==0)begin
       if(pos<8 && card_data!=magic_global(pos[2:0]))bad_header<=1;
       case(pos)
        8:if(card_data!=5)bad_header<=1;
        9,10,11,18,19,22,23,24,26,27,30,31:if(card_data!=0)bad_header<=1;
        12:if(card_data!=8'h80)bad_header<=1;13:if(card_data!=2)bad_header<=1;
        14:if(card_data!=8'he0)bad_header<=1;15:if(card_data!=1)bad_header<=1;
        16:frame_count[7:0]<=card_data;17:frame_count[15:8]<=card_data;
        20:if(card_data!=8'hc3)bad_header<=1;21:if(card_data!=1)bad_header<=1;
        25:if(card_data!=16)bad_header<=1;
        28:nominal_fps[7:0]<=card_data;29:nominal_fps[15:8]<=card_data;
        32:default_threshold<=card_data;
        36:if(VIDEO_ONLY)begin if(card_data!=4)bad_header<=1;end else bmp_count[7:0]<=card_data;
        37:if(VIDEO_ONLY)begin if(card_data!=0)bad_header<=1;end else bmp_count[15:8]<=card_data;
        38:if(VIDEO_ONLY)begin if(card_data!=0)bad_header<=1;end else bmp_count[23:16]<=card_data;
        39:if(VIDEO_ONLY)begin if(card_data!=0)bad_header<=1;end else bmp_count[31:24]<=card_data;
        40,41,42,43:if(!VIDEO_ONLY)bmp_lba[(pos-40)*8+:8]<=card_data;
        44:if(card_data!=2)bad_header<=1;
        45,46,47:if(card_data!=0)bad_header<=1;
        default:;
       endcase
       if(!VIDEO_ONLY&&pos>=48&&pos<64)bmp_crc[(pos-48)>>2][pos[1:0]*8+:8]<=card_data;
      end else if(kind==1&&!VIDEO_ONLY)begin
       if(pos<54)case(pos)
        0:if(card_data!="B")bad_header<=1;1:if(card_data!="M")bad_header<=1;
        10:if(card_data!=54)bad_header<=1;
        11,12,13,15,16,17,20,21,24,25,27,29,30,31,32,33:if(card_data!=0)bad_header<=1;
        14:if(card_data!=40)bad_header<=1;
        18:if(card_data!=8'h80)bad_header<=1;19:if(card_data!=2)bad_header<=1;
        22:if(card_data!=8'he0)bad_header<=1;23:if(card_data!=1)bad_header<=1;
        26:if(card_data!=1)bad_header<=1;28:if(card_data!=24)bad_header<=1;
        default:;
       endcase
       else if(pos<921654)begin
        crc<=crc32_byte(crc,card_data);
        case(bgr_phase)
         0:begin blue<=card_data;bgr_phase<=1;end
         1:begin green<=card_data;bgr_phase<=2;end
         2:begin
          bgr_phase<=0;pixel_half<=~pixel_half;
          if(!pixel_half)pixel0<=rgb565;
          else begin pending_word<={rgb565,pixel0};pending<=1;end
         end
         default:bgr_phase<=0;
        endcase
       end
      end else if(pos<512)begin
       if(pos<8&&card_data!=magic_frame(pos[2:0]))bad_header<=1;
       case(pos)
        8:if(card_data!=index[7:0])bad_header<=1;9:if(card_data!=index[15:8])bad_header<=1;
        10,11,20,23,29,30,31:if(card_data!=0)bad_header<=1;
        21:if(card_data!=8'h84)bad_header<=1;22:if(card_data!=3)bad_header<=1;
                24:expected[7:0]<=card_data;
        25:expected[15:8]<=card_data;
        26:expected[23:16]<=card_data;
        27:expected[31:24]<=card_data;
        28:if(card_data!=2)bad_header<=1;
                36:timestamp_ms[7:0]<=card_data;
        37:timestamp_ms[15:8]<=card_data;
        38:timestamp_ms[23:16]<=card_data;
        39:timestamp_ms[31:24]<=card_data;
        default:;
       endcase
      end else if(pos<total_bytes)begin
       crc<=crc32_byte(crc,card_data);
       case(byte_phase)
        0:accumulator[7:0]<=card_data;1:accumulator[15:8]<=card_data;2:accumulator[23:16]<=card_data;
        3:begin pending_word<={card_data,accumulator};pending<=1;end
       endcase
       byte_phase<=byte_phase+1'b1;
      end
     end
     if(card_done&&seen_busy)begin
      if(pos!=total_bytes)begin error<=4;state<=PAD;end else state<=FINISH;
     end
     if(seen_busy&&card_error!=0)begin error<=card_error;state<=PAD;end
    end
    PAD:begin
     if(!pending&&words_sent<wr_len)begin pending_word<=0;pending<=1;end
     if(words_sent==wr_len&&!pending&&!card_busy)state<=FINISH;
    end
    FINISH:if(!pending&&(wr_len==0 || wd_sync[2]==wr_req_toggle))begin
     // Keep validation compares in their own stage before decoding the public
     // error/result. No object is published until VERIFY completes.
     crc_actual<=~crc;crc_expected<=expected;
     invalid_header<=bad_header || pos!=total_bytes || (kind==0&&(frame_count==0||(!VIDEO_ONLY&&bmp_count!=4)||nominal_fps==0||nominal_fps>60));
     invalid_crc<=kind!=0 && ~crc!=expected;state<=VERIFY;
    end
    VERIFY:begin
     job_done<=1;state<=IDLE;
     if(error!=0)job_ok<=0;
     else if(invalid_header)begin
      error<=kind==0?1:kind==1?2:3;job_ok<=0;
     end else if(invalid_crc)begin error<=kind==1?4'ha:4'h9;job_ok<=0;end
     else begin job_ok<=1;if(kind==0)header_valid<=1;end
    end
    default:state<=IDLE;
   endcase
   if(state!=IDLE&&watchdog>=CLK_HZ*4)begin error<=4'hf;state<=PAD;end
  end
 end
endmodule
