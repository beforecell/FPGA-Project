(* keep_hierarchy="true" *) module bb_reset_release(input clk,input async_reset,output reset);
 (* keep="true" *)wire async_assert=async_reset;
 (* async_reg="true", preserve=1 *)reg [3:0] pipe;
 always @(posedge clk or posedge async_assert)begin if(async_assert)pipe<=4'b1111;else pipe<={pipe[2:0],1'b0};end
 assign reset=pipe[3];
endmodule

// Stable payload held until acknowledged; request has three receive stages,
// bundled payload stays held. Destination can wait for a frame boundary.
module bb_top_mailbox #(parameter WIDTH=1,parameter [WIDTH-1:0] DEFAULT=0)(
 input src_clk,src_rst,src_valid,input [WIDTH-1:0] src_data,
 input dst_clk,dst_rst,dst_apply,output reg [WIDTH-1:0] dst_data,output reg dst_valid);
 reg [WIDTH-1:0] held;reg request,ack;
 (* async_reg="true" *)reg [2:0] rs;
 (* async_reg="true" *)reg [1:0] as;
 // Bundled-data MCP: held is stable from request launch until ack returns.
 // Three request stages give the bus settling time; dst_data samples only
 // after the request arrives. held->dst_data has an explicit max-delay budget.
 always @(posedge src_clk or posedge src_rst)begin
  if(src_rst)begin held<=DEFAULT;request<=0;as<=0;end
  else begin as<={as[0],ack};if(src_valid&&request==as[1])begin held<=src_data;request<=~request;end end
 end
 always @(posedge dst_clk or posedge dst_rst)begin
  if(dst_rst)begin rs<=0;ack<=0;dst_data<=DEFAULT;dst_valid<=0;end
  else begin
   rs<={rs[1:0],request};dst_valid<=0;
   if(dst_apply&&rs[2]!=ack)begin dst_data<=held;ack<=rs[2];dst_valid<=1;end
  end
 end
endmodule
