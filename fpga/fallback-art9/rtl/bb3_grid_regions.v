// Eight distinct source frames of occupancy, not eight HDMI refreshes.
// A seek/gap disables all old bits while the first full grid is overwritten.
module bb3_grid_history #(parameter FRAMES=8)(input clk,rst,invalidate,begin_frame,continuous_frame,
 input valid,input[12:0]addr,input bit_in,output reg ov,output reg[12:0]oa,output reg ob);
 reg usable,v1;reg[12:0]a1;reg b1;wire[6:0]old;
 wire[6:0]next_bits={old[5:0],b1};
 generate if(FRAMES==2)begin:short_history
 wire old_bit;
 bb3_sdp_ram #(.WIDTH(1),.AW(13),.DEPTH(8192)) history(clk,v1,a1,b1,valid,addr,old_bit);
 assign old={6'd0,old_bit};
 end else begin:long_history
 bb3_paged_ram #(.WIDTH(7),.PAGES(5)) history(clk,v1,{1'b0,a1},usable?next_bits:{6'd0,b1},valid,{1'b0,addr},old);
 end endgenerate
 always @(posedge clk)begin
  if(rst)begin usable<=0;v1<=0;a1<=0;b1<=0;ov<=0;oa<=0;ob<=0;end
  else begin
   if(invalidate)usable<=0;else if(begin_frame)usable<=continuous_frame;
   v1<=valid;if(valid)begin a1<=addr;b1<=bit_in;end
   ov<=v1;if(v1)begin oa<=a1;ob<=b1||(usable&&|old);end
  end
 end
endmodule

// Complete 80x60 3x3 morphology raster. Explicit zero output borders; no
// uninitialised RAM can escape. Cells arrive with gaps; flush is autonomous.
module bb3_grid_morph #(parameter ERODE=0)(input clk,rst,input valid,input[12:0]addr,input bit_in,
 output reg ov,output reg[12:0]oa,output reg ob);
 wire[1:0]rq;reg[1:0]h0,h1,h2;reg v1,b1;reg[6:0]x1;reg[5:0]y1;
 reg[6:0]ix;reg[5:0]iy;reg end_col,flush;reg[5:0]end_y;reg[6:0]fx;
 wire a=rq[0],b=rq[1];wire[8:0]window={b1,a,b,h0,h1,h2};
 wire result=ERODE ? &window:|window;
 bb3_sdp_ram #(.WIDTH(2),.AW(7),.DEPTH(128)) rows(clk,v1&&!rst,x1,{a,b1},valid,ix,rq);
 always @(posedge clk)begin
  if(rst)begin ix<=0;iy<=0;v1<=0;b1<=0;x1<=0;y1<=0;end
  else begin
   v1<=valid;
   if(valid)begin
    b1<=bit_in;x1<=ix;y1<=iy;
    if(ix==79)begin ix<=0;iy<=iy==59?0:iy+1'b1;end else ix<=ix+1'b1;
   end
  end
 end
 always @(posedge clk)begin
  if(rst)begin h0<=0;h1<=0;h2<=0;end_col<=0;flush<=0;end_y<=0;fx<=0;ov<=0;oa<=0;ob<=0;end
  else begin
   ov<=0;end_col<=0;
   if(v1)begin
    if(x1==0)begin h0<={1'b0,b1};h1<={1'b0,a};h2<={1'b0,b};end
    else begin h0<={h0[0],b1};h1<={h1[0],a};h2<={h2[0],b};end
    if(x1>=1&&y1>=1)begin ov<=1;oa<=(y1-1'b1)*13'd80+x1-1'b1;ob<=x1>=2&&y1>=2&&result;end
    if(x1==79&&y1>=1)begin end_col<=1;end_y<=y1-1'b1;end
   end
   if(end_col)begin ov<=1;oa<=end_y*13'd80+79;ob<=0;if(end_y==58)begin flush<=1;fx<=0;end end
   if(flush)begin ov<=1;oa<=13'd4720+fx;ob<=0;if(fx==79)flush<=0;else fx<=fx+1'b1;end
  end
 end
endmodule
