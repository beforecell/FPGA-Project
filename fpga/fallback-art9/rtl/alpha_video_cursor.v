// Display timing belongs to the display, not the selected asset. Match the
// cache's two pixel stages even while that cache is reset or has no valid frame.
module alpha_video_cursor(input clk,rst,frame_start,hs,vs,de,
 output reg ohs,ovs,ode,output reg[9:0]x,output reg[8:0]y);
 reg[9:0]cx,qx;reg[8:0]cy,qy;reg last_de,qhs,qvs,qde;
 always @(posedge clk)begin
  if(rst)begin cx<=0;cy<=0;last_de<=0;qx<=0;qy<=0;qhs<=0;qvs<=0;qde<=0;
   ohs<=0;ovs<=0;ode<=0;x<=0;y<=0;
  end else begin
   last_de<=de;
   if(!de)cx<=0;else cx<=cx+1'b1;
   if(last_de&&!de)cy<=cy+1'b1;
   if(frame_start)begin cx<=0;cy<=0;end
   qhs<=hs;qvs<=vs;qde<=de;qx<=cx;qy<=cy;
   ohs<=qhs;ovs<=qvs;ode<=qde;x<=qx;y<=qy;
  end
 end
endmodule
