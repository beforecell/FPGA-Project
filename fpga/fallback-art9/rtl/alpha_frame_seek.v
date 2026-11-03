// Pause is owned by UI. Seek both source-sample time and PCM to a frame boundary.
module alpha_frame_seek(input clk,rst,cancel,next,previous,input[15:0]displayed_frame,frame_count,fps,
 input clock_ack,input[15:0]committed_frame,input cache_valid,audio_ready,pcm_flush,
 output reg busy,request_toggle,audio_seek,output reg[15:0]target_frame,frame_phase,
 output reg[31:0]sample_position,milliseconds,output reg[5:0]ms_phase);
 reg[2:0]state;reg[31:0]numer,quot;reg[16:0]rem;reg[15:0]denom;reg[5:0]bit_count;
 wire[16:0]nr={rem[15:0],numer[31]};wire ge=nr>=denom;wire[31:0]nq={quot[30:0],ge};wire[16:0]rr=ge ? nr-denom:nr;
 wire[15:0]goal=next ? (displayed_frame+17'd1<frame_count ? displayed_frame+1'b1:frame_count-1'b1):(displayed_frame==0 ? 0:displayed_frame-1'b1);
 always @(posedge clk)begin
  if(rst)begin state<=0;busy<=0;request_toggle<=0;audio_seek<=0;target_frame<=0;frame_phase<=0;sample_position<=0;milliseconds<=0;ms_phase<=0;numer<=0;quot<=0;rem<=0;denom<=1;bit_count<=0;end
  else begin
   audio_seek<=0;
   if(cancel)begin busy<=0;state<=0;end
   else case(state)
    0:if((next||previous)&&frame_count!=0&&fps!=0)begin busy<=1;target_frame<=goal;quot<=0;rem<=0;denom<=fps;bit_count<=0;state<=6;end
    // Bound/step logic and the sample-address multiply use separate cycles.
    // Inputs may change after request; target_frame and fps are already held.
    6:begin numer<=target_frame*32'd48000;state<=1;end
    1:begin numer<={numer[30:0],1'b0};quot<=nq;rem<=rr;bit_count<=bit_count+1'b1;
     if(bit_count==31)begin sample_position<=nq+(rr!=0);frame_phase<=rr!=0 ? denom-rr:0;state<=2;end
    end
    2:begin numer<=sample_position;quot<=0;rem<=0;denom<=48;bit_count<=0;state<=3;end
    3:begin numer<={numer[30:0],1'b0};quot<=nq;rem<=rr;bit_count<=bit_count+1'b1;
     if(bit_count==31)begin milliseconds<=nq;ms_phase<=rr[5:0];state<=4;end
    end
    4:begin request_toggle<=~request_toggle;audio_seek<=1;state<=5;end
    5:if(clock_ack==request_toggle&&committed_frame==target_frame&&cache_valid&&audio_ready&&!pcm_flush)begin busy<=0;state<=0;end
    default:state<=0;
   endcase
  end
 end
endmodule
