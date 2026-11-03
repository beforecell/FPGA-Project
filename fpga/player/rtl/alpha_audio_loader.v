// Request/track changes wait for the old transaction and discard its tail.
// 8-sector refill = 2048 samples. FIFO covers > one normal video object read.
module alpha_audio_loader(input clk,rst,input restart,cue_start,cancel,input[1:0]cue_index,
 input[31:0]media_lba,media_samples,resume_sample,
 input[31:0]c0_lba,c1_lba,c2_lba,c3_lba,c0_samples,c1_samples,c2_samples,c3_samples,
 input cue_finished,input card_busy,card_done,card_valid,input[7:0]card_data,input[3:0]card_error,
 output reg card_start,output reg[31:0]card_lba,output[31:0]card_blocks,output card_ready,
 output reg flush,output reg fifo_we,output reg[15:0]fifo_data,input fifo_full,input[13:0]fifo_count,
 output reg cue_mode,track_ready,cue_done,output reg[31:0]track_samples,output reg[3:0]error,
 input seek_start,input[31:0]seek_sample);
 reg[2:0]state;reg[5:0]flush_count;reg[31:0]base,total,offset,left,pending_base,pending_total,pending_offset;
 reg prefilled,refill_low,buffered;reg pending_cue;reg[7:0]lo,skip_left,pending_skip;reg bytephase;reg[12:0]bytes_seen;reg discard;
 assign card_blocks=8;assign card_ready=discard||!fifo_full;
 always @(posedge clk)begin
  if(rst)begin state<=0;flush_count<=0;card_start<=0;card_lba<=0;flush<=1;fifo_we<=0;fifo_data<=0;cue_mode<=0;track_ready<=0;cue_done<=0;track_samples<=0;error<=0;
   prefilled<=0;refill_low<=1;buffered<=0;base<=0;total<=0;offset<=0;left<=0;pending_base<=0;pending_total<=0;pending_offset<=0;pending_cue<=0;lo<=0;bytephase<=0;bytes_seen<=0;discard<=1;skip_left<=0;pending_skip<=0;
  end else begin
   card_start<=0;fifo_we<=0;cue_done<=0;prefilled<=fifo_count>=2048;refill_low<=fifo_count<=4096;buffered<=fifo_count!=0;
   if(seek_start||restart||cue_start||cancel||(cue_finished&&cue_mode))begin
    discard<=1;track_ready<=0;state<=1;error<=0;
    if(cue_start&&!seek_start)begin
     pending_cue<=1;pending_offset<=0;pending_skip<=0;
     case(cue_index)0:begin pending_base<=c0_lba;pending_total<=c0_samples;end
      1:begin pending_base<=c1_lba;pending_total<=c1_samples;end
      2:begin pending_base<=c2_lba;pending_total<=c2_samples;end
      3:begin pending_base<=c3_lba;pending_total<=c3_samples;end endcase
    end else begin
     pending_cue<=0;pending_base<=media_lba;pending_total<=media_samples;pending_offset<=seek_start ? (seek_sample&32'hffffff00):restart ? 0:(resume_sample&32'hffffff00);pending_skip<=seek_start ? seek_sample[7:0]:restart ? 0:resume_sample[7:0];
     if(cue_finished&&cue_mode)cue_done<=1;
    end
   end else case(state)
    0:;
    1:if(!card_busy)begin flush<=1;flush_count<=0;state<=2;end
    2:begin
     flush_count<=flush_count+1'b1;
     if(flush_count==31)begin
      base<=pending_base;total<=pending_total;offset<=pending_offset;left<=pending_total>pending_offset ? pending_total-pending_offset:0;
      cue_mode<=pending_cue;track_samples<=pending_total>pending_offset ? pending_total-pending_offset:0;discard<=0;flush<=0;bytephase<=0;skip_left<=pending_skip;state<=3;
      if(pending_total==0&&pending_cue)begin
       cue_done<=1;cue_mode<=0;pending_cue<=0;pending_base<=media_lba;pending_total<=media_samples;pending_offset<=resume_sample&32'hffffff00;pending_skip<=resume_sample[7:0];state<=1;
      end
     end
    end
    3:begin
     if(total==0||left==0)track_ready<=1;
     if(prefilled||(left==0&&buffered))track_ready<=1;
     if(left!=0&&refill_low&&!card_busy)begin card_lba<=base+(offset>>8);card_start<=1;bytes_seen<=0;bytephase<=0;state<=4;end
    end
    4:begin
     if(card_valid&&card_ready)begin
      bytes_seen<=bytes_seen+1'b1;bytephase<=~bytephase;
      if(!bytephase)lo<=card_data;
      else if(left!=0)begin
       if(skip_left!=0)skip_left<=skip_left-1'b1;else begin fifo_data<={card_data,lo};fifo_we<=1;end
       left<=left-1'b1;offset<=offset+1'b1;
      end
     end
     if(card_done)begin state<=3;if(card_error!=0)begin error<=card_error;track_ready<=0;state<=0;end end
    end
    default:state<=0;
   endcase
  end
 end
endmodule
