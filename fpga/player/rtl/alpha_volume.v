// Master PCM amplitude:0..100 percent, linear amplitude, all media and beeps.
// FFT/waveform remain on the original media-only branch before this module.
// Q15 gain lookup is an algorithm constant, not precomputed media analysis.
module alpha_volume(input clk,rst,input valid,input signed[23:0]pcm,
 input[7:0]percent,output reg out_valid,output reg signed[23:0]out_pcm);
 (* ram_style="bram" *)reg[15:0]gains[0:127];integer i;
 reg[15:0]target,gain;reg signed[32:0]product;reg pending;
 wire[6:0]address=percent>100?7'd100:percent[6:0];
 initial for(i=0;i<128;i=i+1)gains[i]=(i>100?32768:(i*32768+50)/100);
 always @(posedge clk)target<=gains[address];
 wire signed[32:0]rounded=product+(product<0?33'sd16383:33'sd16384);
 always @(posedge clk)begin
  if(rst)begin gain<=0;product<=0;pending<=0;out_valid<=0;out_pcm<=0;end
  else begin
   pending<=valid;out_valid<=pending;
   if(valid)begin
    // At most128 samples (2.667ms at48kHz) for a full-range gain ramp.
    if(gain<target)gain<=target-gain>256?gain+256:target;
    else if(gain>target)gain<=gain-target>256?gain-256:target;
    product<=$signed(pcm[23:8])*$signed({1'b0,gain});
   end
   if(pending)out_pcm<={rounded[30:15],8'd0};
  end
 end
endmodule
