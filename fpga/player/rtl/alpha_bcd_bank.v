// Four HUD numbers share one decimal subtractor. Worst-case refresh <10us
// at25MHz; no pixel backpressure, outputs remain stable until each word completes.
module alpha_bcd_bank(input clk,rst,input[15:0]frame_id,width,height,hz,
 output reg[19:0]frame_bcd,width_bcd,height_bcd,hz_bcd);
 reg[1:0]bank;reg[2:0]digit_index;reg[15:0]remaining;reg[19:0]accum;
 reg[3:0]digit;reg loading;
 wire[15:0]input_value=bank==0?frame_id:bank==1?width:bank==2?height:hz;
 reg[15:0]threshold;
 always @*case(digit_index)0:threshold=10000;1:threshold=1000;2:threshold=100;3:threshold=10;default:threshold=1;endcase
 wire[19:0]completed={accum[15:0],digit};
 always @(posedge clk)begin
  if(rst)begin bank<=0;digit_index<=0;remaining<=0;accum<=0;digit<=0;loading<=1;frame_bcd<=0;width_bcd<=0;height_bcd<=0;hz_bcd<=0;end
  else if(loading)begin remaining<=input_value;accum<=0;digit<=0;digit_index<=0;loading<=0;end
  else if(remaining>=threshold)begin remaining<=remaining-threshold;digit<=digit+1'b1;end
  else if(digit_index==4)begin
   case(bank)0:frame_bcd<=completed;1:width_bcd<=completed;2:height_bcd<=completed;3:hz_bcd<=completed;endcase
   bank<=bank+1'b1;loading<=1;
  end else begin accum<=completed;digit<=0;digit_index<=digit_index+1'b1;end
 end
endmodule
