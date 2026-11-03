// Actual decoded RGB inputs only. No stored masks or frame-index lookup.
// Two pixel pipeline stages; 2x2 causal 3-of-4, anchored on current pixel.
// First row/column of each pane are zero. Prior row overwritten every raster.
module alpha_frame_difference(input clk,rst,de,quad_mode,pair_valid,
 input[9:0]x,input[8:0]y,input[23:0]current,previous,input[7:0]threshold,
 output reg mask);
 wire[15:0]c=current[23:16]*16'd77+current[15:8]*16'd150+current[7:0]*16'd29;
 wire[15:0]p=previous[23:16]*16'd77+previous[15:8]*16'd150+previous[7:0]*16'd29;
 wire[7:0]d=c[15:8]>p[15:8] ? c[15:8]-p[15:8]:p[15:8]-c[15:8];
 reg valid1,raw1,first_x,first_y,left,upper_left;reg[9:0]x1;
 wire upper;wire[2:0]votes={2'd0,raw1}+{2'd0,left}+{2'd0,upper}+{2'd0,upper_left};
 bb3_sdp_ram #(.WIDTH(1),.AW(10),.DEPTH(1024)) rowbits(clk,valid1,x1,raw1,de,x,upper);
 always @(posedge clk)begin
  if(rst)begin valid1<=0;raw1<=0;x1<=0;first_x<=1;first_y<=1;left<=0;upper_left<=0;mask<=0;end
  else begin
   valid1<=de;raw1<=pair_valid&&d>threshold;x1<=x;
   first_x<=x==0||(quad_mode&&x==320);first_y<=y==0||(quad_mode&&y==240);
   mask<=valid1&&raw1&&!first_x&&!first_y&&votes>=3;
   if(valid1)begin left<=raw1;upper_left<=upper;end
  end
 end
endmodule
