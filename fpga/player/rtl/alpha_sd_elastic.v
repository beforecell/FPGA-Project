// Two-byte elastic queue isolates SD pin timing from client ready logic.
// Completion/error is published only after all buffered bytes are consumed.
module alpha_sd_elastic(input clk,rst,phy_busy,phy_done,phy_valid,input[7:0]phy_data,
 input[3:0]phy_error,output phy_ready,output busy,output reg done,output valid,
 output[7:0]data,output reg[3:0]error,input ready);
 reg[7:0]q0,q1;reg[1:0]count;reg finished;
 wire push=phy_valid&&phy_ready,pop=valid&&ready;
 assign phy_ready=count<2;assign valid=count!=0;assign data=q0;
 assign busy=phy_busy||count!=0||finished;
 always @(posedge clk)begin
  if(rst)begin count<=0;q0<=0;q1<=0;finished<=0;done<=0;error<=0;end
  else begin
   done<=0;
   case({push,pop})
    2'b10:begin if(count==0)q0<=phy_data;else q1<=phy_data;count<=count+1'b1;end
    2'b01:begin q0<=q1;count<=count-1'b1;end
    2'b11:begin q0<=phy_data;end
    default:;
   endcase
   if(phy_done)begin finished<=1;error<=phy_error;end
   if(finished&&count==0&&!phy_busy)begin finished<=0;done<=1;end
  end
 end
endmodule
