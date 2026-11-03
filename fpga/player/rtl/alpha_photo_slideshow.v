// Photo-only wall-clock dwell timer; starts from a fully ready/stable image.
// Enable toggles, manual navigation, open/load/transition and return reset dwell.
// One request is issued, then held off until media control acknowledges by busy/open.
module alpha_photo_slideshow #(parameter CLK_HZ=50000000,HOLD_MS=5000)(
 input clk,rst,enable,image_mode,browser,ready,busy,opened,manual_switch,
 output reg advance);
 localparam TICKS=CLK_HZ/1000;
 reg[$clog2(TICKS+1)-1:0]sub_ms;reg[$clog2(HOLD_MS+1)-1:0]elapsed;
 reg enabled_last,waiting;
 always @(posedge clk)begin
  if(rst)begin sub_ms<=0;elapsed<=0;enabled_last<=0;waiting<=0;advance<=0;end
  else begin
   advance<=0;enabled_last<=enable;
   if(!enable||enable!=enabled_last||!image_mode||browser||!ready||busy||opened||manual_switch)begin sub_ms<=0;elapsed<=0;waiting<=0;end
   else if(!waiting)begin
    if(sub_ms==TICKS-1)begin sub_ms<=0;
     if(elapsed==HOLD_MS-1)begin elapsed<=0;advance<=1;waiting<=1;end
     else elapsed<=elapsed+1'b1;
    end else sub_ms<=sub_ms+1'b1;
   end
  end
 end
endmodule
