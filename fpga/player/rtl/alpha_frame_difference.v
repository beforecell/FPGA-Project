// Runtime adaptive frame difference and binary inner contour.No stored results.
// One pixel/clock,two clock pipeline stages,matching the existing renderer.
// Two causal3x3 windows center on input(x-2,y-2):a2screen-pixel spatial
// offset,not two frames of lag.First4rows/columns of each pane are black.
module alpha_frame_difference #(parameter DARK_LEVEL=64,
 parameter DARK_DIFF_LOW=6,DARK_DIFF_HIGH=12,BRIGHT_DIFF_LOW=10
)(input clk,rst,de,quad_mode,pair_valid,
 input[9:0]x,input[8:0]y,input[23:0]current,previous,input[7:0]threshold,
 output reg mask);
 wire[15:0]cy=current[23:16]*16'd77+current[7:0]*16'd29+current[15:8]*16'd150;
 wire[15:0]py=previous[23:16]*16'd77+previous[7:0]*16'd29+previous[15:8]*16'd150;
 wire[7:0]delta=cy[15:8]>py[15:8]?cy[15:8]-py[15:8]:py[15:8]-cy[15:8];
 reg valid1,pair1,quad1;reg[9:0]x1;reg[8:0]y1;reg[1:0]raw1;
 wire[3:0]raw_rows;
 // Two prior rows of weak/strong flags,then two prior binary mask rows.
 // No grayscale/gradient storage:two logical memories,packed into one32K bank by TD.
 bb3_sdp_ram #(.WIDTH(4),.AW(10),.DEPTH(1024),.IMPLEMENT("32K")) raw_lines(
 clk,valid1,x1,{raw_rows[1:0],raw1},de,x,raw_rows);
 reg[1:0]r0l1,r0l2,r1l1,r1l2,r2l1,r2l2;
 wire[1:0]r[0:8];
 assign r[0]=r2l2;assign r[1]=r2l1;assign r[2]=raw_rows[3:2];
 assign r[3]=r1l2;assign r[4]=r1l1;assign r[5]=raw_rows[1:0];
 assign r[6]=r0l2;assign r[7]=r0l1;assign r[8]=raw1;
 wire raw_dark=cy[15:8]<DARK_LEVEL;
 wire raw_weak=delta>(raw_dark?DARK_DIFF_LOW:BRIGHT_DIFF_LOW);
 wire raw_strong=delta>(raw_dark?DARK_DIFF_HIGH:threshold);
 wire[8:0]diff_weak_bits,diff_strong_bits;
 genvar i;generate for(i=0;i<9;i=i+1)begin:diff_thresholds
  assign diff_weak_bits[i]=r[i][0];assign diff_strong_bits[i]=r[i][1];
 end endgenerate
 wire[3:0]votes={3'd0,diff_weak_bits[0]}+{3'd0,diff_weak_bits[1]}+{3'd0,diff_weak_bits[2]}+
 {3'd0,diff_weak_bits[3]}+{3'd0,diff_weak_bits[4]}+{3'd0,diff_weak_bits[5]}+{3'd0,diff_weak_bits[6]}+{3'd0,diff_weak_bits[7]}+{3'd0,diff_weak_bits[8]};
 // Coherent weak changes must meet a local weak/background boundary;
 // strong changes remain eligible throughout their local neighborhood.
 wire supported=votes>=2&&((|diff_strong_bits)||(votes>=3&&votes<9));
 wire raw_border_ok=x1>=2&&y1>=2&&(!quad1||((x1<320||x1>=322)&&(y1<240||y1>=242)));
 wire motion_gate=valid1&&pair1&&raw_border_ok&&supported;
 wire feature=motion_gate;
 wire[1:0]feature_rows;
 bb3_sdp_ram #(.WIDTH(2),.AW(10),.DEPTH(1024),.IMPLEMENT("32K")) contour_lines(
 clk,valid1,x1,{feature_rows[0],feature},de,x,feature_rows);
 reg g0l1,g0l2,g1l1,g1l2,g2l1,g2l2;
 wire g[0:8];
 assign g[0]=g2l2;assign g[1]=g2l1;assign g[2]=feature_rows[1];
 assign g[3]=g1l2;assign g[4]=g1l1;assign g[5]=feature_rows[0];
 assign g[6]=g0l2;assign g[7]=g0l1;assign g[8]=feature;
 // Inner morphological gradient M minus erode_cross(M). Draw only the
 // one-sample boundary of the actual temporal mask,not static source edges.
 wire thin=g[4]&&!(g[1]&&g[3]&&g[5]&&g[7]);
 wire border_ok=x1>=4&&y1>=4&&(!quad1||((x1<320||x1>=324)&&(y1<240||y1>=244)));
 always @(posedge clk)begin
  // Valid/output need reset;stream data does not.Unreset coordinates can
  // share the renderer's existing first-stage registers instead of creating
  // another reset control set.The four-row/column guard still flushes RAM.
  valid1<=de&&!rst;
  if(rst)mask<=0;else mask<=valid1&&pair1&&border_ok&&thin;
  pair1<=pair_valid;quad1<=quad_mode;x1<=x;y1<=y;raw1<={raw_strong,raw_weak};
 end
 // Shift through blanking without CE/reset.Controls/line RAM still use de;
 // the first4columns/rows mask all stale neighborhood values before display.
 always @(posedge clk)begin
  r0l1<=raw1;r0l2<=r0l1;r1l1<=raw_rows[1:0];r1l2<=r1l1;r2l1<=raw_rows[3:2];r2l2<=r2l1;
  g0l1<=feature;g0l2<=g0l1;g1l1<=feature_rows[0];g1l2<=g1l1;g2l1<=feature_rows[1];g2l2<=g2l1;
 end
endmodule
