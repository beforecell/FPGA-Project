module alpha_audio_out(input clk,rst,flush,input sample_ce,paused,muted,video_ready,has_audio,cue_mode,track_ready,
 input[31:0]track_samples,input fifo_empty,fifo_valid,input[15:0]fifo_data,output fifo_pop,
 input beep,input[1:0]beep_kind,output reg cue_finished,output media_advance,
 output reg sample_valid,output reg[23:0]pcm,output reg fft_valid,output reg signed[15:0]fft_sample,
 output reg[31:0]underflows);
 reg held,pending,primed;reg[15:0]word;reg[19:0]cue_played;reg cue_was;
 // Ready crosses independently of the FIFO's synchronous first-word read.
 // Arm once that word is held; do not hide starvation after playback starts.
 wire active=track_ready&&primed&&(cue_mode||(!paused&&video_ready));
 wire consume=sample_ce&&active&&held;
 assign fifo_pop=!fifo_empty&&!held&&!pending&&track_ready;
 assign media_advance=!paused&&video_ready&&!cue_mode&&(!has_audio||(track_ready&&primed&&held));
 reg[31:0]tone_phase,step;reg[11:0]tone_left,age;
 wire[5:0]gain=age<48 ? age[5:0]:tone_left<48 ? tone_left[5:0]:6'd48;
 wire[14:0]tri_abs=tone_phase[30] ? 15'd32767-tone_phase[29:15]:tone_phase[29:15];
 wire signed[15:0]triangle=tone_phase[31] ? -$signed({1'b0,tri_abs}):$signed({1'b0,tri_abs});
 wire signed[22:0]tone_product=triangle*$signed({1'b0,gain});
 wire signed[16:0]media_value=muted ? 17'sd0:held ? $signed({word[15],word}):17'sd0;
 wire signed[17:0]mixed=cue_mode ? media_value:tone_left!=0 ? (media_value>>>1)+(tone_product>>>8):media_value;
 wire[15:0]limited=mixed>32767 ? 16'h7fff:mixed< -32768 ? 16'h8000:mixed[15:0];
 always @(posedge clk)begin
  if(rst||flush)begin held<=0;pending<=0;primed<=0;word<=0;cue_played<=0;cue_was<=0;cue_finished<=0;sample_valid<=rst ? 0:sample_ce;pcm<=0;fft_valid<=0;fft_sample<=0;if(rst)underflows<=0;tone_phase<=0;step<=0;tone_left<=0;age<=0;end
  else begin
   cue_finished<=0;sample_valid<=sample_ce;fft_valid<=0;cue_was<=cue_mode;
   if(!track_ready)primed<=0;else if(held)primed<=1;
   if(cue_mode&&!cue_was)cue_played<=0;
   if(fifo_pop)pending<=1;
   if(fifo_valid)begin word<=fifo_data;held<=1;pending<=0;end
   if(consume)begin held<=0;if(cue_mode)begin cue_played<=cue_played+1'b1;if(cue_played+1>=track_samples)cue_finished<=1;end end
   if(beep)begin tone_left<=1440;age<=0;tone_phase<=0;case(beep_kind)0:step<=71582788;1:step<=107374182;2:step<=53687091;3:step<=35791394;endcase end
   if(sample_ce)begin
    if(tone_left!=0)begin tone_left<=tone_left-1'b1;age<=age+1'b1;tone_phase<=tone_phase+step;end
    pcm<=muted ? 24'd0:active ? {limited,8'd0}:tone_left!=0&&!cue_mode ? {tone_product[23-1:7],8'd0}:24'd0;
    if(!cue_mode&&!paused&&video_ready&&has_audio&&track_ready&&primed&&held)begin fft_valid<=1;fft_sample<=word;end
    if(active&&(has_audio||cue_mode)&&!held)underflows<=underflows+1'b1;
   end
  end
 end
endmodule
