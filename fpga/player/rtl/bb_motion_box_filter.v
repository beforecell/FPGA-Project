// Suppress contained duplicate region boxes after CCL; stable input until done.
// No class recognition, no union of nearby independent vehicles, no stale history.
module bb_motion_box_filter(input clk,rst,start,input[3:0]valid_in,input[111:0]boxes,
 output reg busy,done,output reg[3:0]valid_out);
 reg[1:0]a,b;
 wire[27:0]ba=boxes[a*28+:28],bb=boxes[b*28+:28];
 wire contained=ba[6:0]>=bb[6:0]&&ba[13:7]<=bb[13:7]&&ba[20:14]>=bb[20:14]&&ba[27:21]<=bb[27:21];
 wire strict=ba!=bb;
 always @(posedge clk)begin
  if(rst)begin a<=0;b<=0;busy<=0;done<=0;valid_out<=0;end
  else begin
   done<=0;
   if(start&&!busy)begin a<=0;b<=0;busy<=1;valid_out<=valid_in;end
   else if(busy)begin
    // Original validity avoids order-dependent removal when nested repeatedly.
    if(a!=b&&valid_in[a]&&valid_in[b]&&contained&&(strict||b<a))valid_out[a]<=0;
    if(b==3)begin b<=0;if(a==3)begin busy<=0;done<=1;end else a<=a+1'b1;end else b<=b+1'b1;
   end
  end
 end
endmodule
