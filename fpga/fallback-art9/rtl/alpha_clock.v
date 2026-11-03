// Media clock counts accepted media sample times, not video refreshes.
// HDMI sample carrier never stops. Cue playback does not advance this clock.
module alpha_clock #(parameter PIXEL_HZ=25000000,SAMPLE_HZ=48000)(
 input clk,rst,restart,advance,input[15:0]fps,frame_count,
 output reg sample_ce,output reg[31:0]samples,media_ms,output reg[15:0]frame_id,
 output[7:0]fraction,output reg loop_pulse,
 input[10:0]rate_q8_8,input seek,input[31:0]seek_samples,seek_ms,input[15:0]seek_frame,seek_frame_phase,input[5:0]seek_ms_phase,output reg[31:0]elapsed_samples);
 reg[7:0]rate_phase;reg[2:0]ticks_left;wire[11:0]rate_sum={4'd0,rate_phase}+{1'b0,rate_q8_8};
 reg[25:0]carrier;reg[$clog2(SAMPLE_HZ/1000)-1:0]ms_phase;reg[15:0]frame_phase;
 wire[26:0]sum={1'b0,carrier}+SAMPLE_HZ;
 wire[16:0]fp={1'b0,frame_phase}+fps;
 // Q22 reciprocal: at48k,22370/2^22 approximates256/48000 within1/256.
 // A registered small multiplier replaces a wide combinational constant divider.
 reg[31:0]phase_product;
 always @(posedge clk)if(rst)phase_product<=0;else phase_product<=frame_phase*16'd22370;
 assign fraction=phase_product[29:22];
 always @(posedge clk)begin
  if(rst)begin elapsed_samples<=0;rate_phase<=0;ticks_left<=0;carrier<=0;sample_ce<=0;samples<=0;media_ms<=0;frame_id<=0;ms_phase<=0;frame_phase<=0;loop_pulse<=0;end
  else begin
   sample_ce<=sum>=PIXEL_HZ;carrier<=sum>=PIXEL_HZ ? sum-PIXEL_HZ:sum;loop_pulse<=0;
   if(restart)begin elapsed_samples<=0;rate_phase<=0;ticks_left<=0;samples<=0;media_ms<=0;frame_id<=0;ms_phase<=0;frame_phase<=0;end
   else if(seek)begin samples<=seek_samples;media_ms<=seek_ms;frame_id<=seek_frame;frame_phase<=seek_frame_phase;ms_phase<=seek_ms_phase;rate_phase<=0;ticks_left<=0;end
   else begin
    if(sample_ce&&advance)begin rate_phase<=rate_sum[7:0];ticks_left<=rate_sum[10:8];end
    if(ticks_left!=0)begin ticks_left<=ticks_left-1'b1;elapsed_samples<=elapsed_samples+1'b1;
    samples<=samples+1'b1;
    if(ms_phase==SAMPLE_HZ/1000-1)begin ms_phase<=0;media_ms<=media_ms+1'b1;end else ms_phase<=ms_phase+1'b1;
    if(fp>=SAMPLE_HZ)begin
     frame_phase<=fp-SAMPLE_HZ;
     if(frame_id+1>=frame_count)begin frame_id<=0;samples<=0;media_ms<=0;ms_phase<=0;loop_pulse<=1;end
     else frame_id<=frame_id+1'b1;
    end else frame_phase<=fp[15:0];
    end
   end
  end
 end
endmodule

module alpha_blend(input clk,input[23:0]a,b,input[7:0]phase,output reg[23:0]rgb);
 wire[8:0]inv=9'd256-{1'b0,phase};
 wire[16:0]r=a[23:16]*inv+b[23:16]*{1'b0,phase}+17'd128;
 wire[16:0]g=a[15:8]*inv+b[15:8]*{1'b0,phase}+17'd128;
 wire[16:0]c=a[7:0]*inv+b[7:0]*{1'b0,phase}+17'd128;
 wire[7:0]dr=a[23:16]>b[23:16]?a[23:16]-b[23:16]:b[23:16]-a[23:16];
 wire[7:0]dg=a[15:8]>b[15:8]?a[15:8]-b[15:8]:b[15:8]-a[15:8];
 wire[7:0]db=a[7:0]>b[7:0]?a[7:0]-b[7:0]:b[7:0]-a[7:0];
 // Strongly changed/occluded pixels use a whole RGB endpoint. This removes
 // double-exposure ghosts; it is NOT motion estimation or MEMC interpolation.
 always @(posedge clk)rgb<=phase==0?a:phase==255?b:
  (dr>32||dg>32||db>32)?(phase[7]?b:a):{r[15:8],g[15:8],c[15:8]};
endmodule
