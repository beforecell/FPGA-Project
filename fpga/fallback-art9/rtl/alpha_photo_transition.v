// 8x6 hardware domino reveal,18 display frames (~302.4ms at25MHz VGA).
// Both RGB565 pictures are live SDRAM cache reads, not a pre-rendered video.
module alpha_photo_transition #(parameter FRAMES=18)(input clk,rst,frame_start,accepted,image_mode,history_valid,browser,backwards,
 input[9:0]x,input[8:0]y,input[23:0]new_rgb,old_rgb,
 output[23:0]rgb,output reg busy);
 reg[4:0]age;reg reverse;reg[5:0]revealed;
 wire[2:0]tx=x>=560?7:x>=480?6:x>=400?5:x>=320?4:x>=240?3:x>=160?2:x>=80?1:0;
 wire[2:0]ty=y>=400?5:y>=320?4:y>=240?3:y>=160?2:y>=80?1:0;
 wire[5:0]rank={ty,tx};wire[5:0]order=reverse ? 6'd47-rank:rank;
 assign rgb=busy&&order>=revealed ? old_rgb:new_rgb;
 generate if(FRAMES==18)begin
 always @*begin
  case(age)
   0:revealed=6'd0;
   1:revealed=6'd2;
   2:revealed=6'd5;
   3:revealed=6'd8;
   4:revealed=6'd10;
   5:revealed=6'd13;
   6:revealed=6'd16;
   7:revealed=6'd18;
   8:revealed=6'd21;
   9:revealed=6'd24;
   10:revealed=6'd26;
   11:revealed=6'd29;
   12:revealed=6'd32;
   13:revealed=6'd34;
   14:revealed=6'd37;
   15:revealed=6'd40;
   16:revealed=6'd42;
   17:revealed=6'd45;
   18:revealed=6'd48;
   default:revealed=48;
  endcase
 end
 end else begin always @*revealed=age*48/FRAMES;end endgenerate
 always @(posedge clk)begin
  if(rst)begin busy<=0;age<=FRAMES;reverse<=0;end
  else if(browser||!image_mode)begin busy<=0;age<=FRAMES;end
  else if(accepted)begin busy<=history_valid;age<=history_valid ? 0:FRAMES;reverse<=backwards;end
  else if(frame_start&&busy)begin if(age==FRAMES-1)begin age<=FRAMES;busy<=0;end else age<=age+1'b1;end
 end
endmodule
