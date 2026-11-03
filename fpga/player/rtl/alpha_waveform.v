// Media PCM only:256 signed min/max bins,1024 consecutive48kHz samples/bin.
// History spans5.461333s. A512-bin ring protects the256-bin HDMI snapshot.
// Pause holds it; reset/seek clears it. No offline points are accepted.
module alpha_waveform #(parameter BIN_SAMPLES=1024)(input clk,rst,enabled,frame_start,valid,input signed[15:0]sample,
 input[7:0]query,output signed[15:0]minimum,maximum,output reg display_valid,
 output reg[7:0]energy_level,output reg[8:0]history_bins,output reg completed);
 reg[8:0]write_pos,shown_end,filled,shown_count;reg[10:0]within_bin;
 reg signed[15:0]lo,hi;
 reg[40:0]sum_squares;wire signed[31:0]square=sample*sample;
 wire[40:0]next_sum=sum_squares+{9'd0,square};
 wire signed[15:0]next_lo=within_bin==0||sample<lo ? sample:lo;
 wire signed[15:0]next_hi=within_bin==0||sample>hi ? sample:hi;
 wire we=enabled&&valid&&within_bin==BIN_SAMPLES-1;
 wire[8:0]read_pos=shown_end-9'd256+{1'b0,query};wire[31:0]q;
 reg query_valid;reg[7:0]latest_energy;
 bb3_sdp_ram #(.WIDTH(32),.AW(9),.DEPTH(512)) history(clk,we,write_pos,{next_lo,next_hi},1'b1,read_pos,q);
 always @(posedge clk)query_valid<=!rst&&enabled&&display_valid&&({1'b0,query}>=9'd256-shown_count);
 assign minimum=query_valid ? $signed(q[31:16]):16'sd0;
 assign maximum=query_valid ? $signed(q[15:0]):16'sd0;
 always @(posedge clk)begin
  if(rst||!enabled)begin
   write_pos<=0;shown_end<=0;filled<=0;shown_count<=0;within_bin<=0;lo<=0;hi<=0;
   sum_squares<=0;display_valid<=0;latest_energy<=0;energy_level<=0;history_bins<=0;completed<=0;
  end else begin
   completed<=0;
   if(valid)begin
    lo<=next_lo;hi<=next_hi;
    if(we)begin
     within_bin<=0;sum_squares<=0;write_pos<=write_pos+1'b1;completed<=1;
     if(filled<256)filled<=filled+1'b1;
     // Mean-square / full-scale-square *256;1024samples,15 magnitude bits.
     latest_energy<=next_sum[40] ? 8'd255:next_sum[39:32];
    end else begin within_bin<=within_bin+1'b1;sum_squares<=next_sum;end
   end
   if(frame_start)begin
    shown_end<=write_pos;shown_count<=filled;display_valid<=filled!=0;
    energy_level<=latest_energy;history_bins<=filled;
   end
  end
 end
endmodule
