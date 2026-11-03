module alpha_time_dual(input clk,rst,input[31:0]current_ms,total_ms,output reg[31:0]current_bcd,total_bcd);
 reg[31:0]remaining;reg[2:0]state;reg select_total;reg[7:0]h,m,s,c;
 function[7:0]inc;input[7:0]v;begin inc=v[3:0]==9 ? {v[7:4]+4'd1,4'd0}:v+1'b1;end endfunction
 reg[31:0]threshold;
 always @*case(state)1:threshold=3600000;2:threshold=60000;3:threshold=1000;default:threshold=10;endcase
 wire enough=remaining>=threshold;wire[31:0]difference=remaining-threshold;
 always @(posedge clk)begin
  if(rst)begin remaining<=0;state<=0;select_total<=0;h<=0;m<=0;s<=0;c<=0;current_bcd<=0;total_bcd<=0;end
  else begin
   if(state>=1&&state<=4&&enough)remaining<=difference;
   case(state)
   0:begin remaining<=select_total ? total_ms:current_ms;h<=0;m<=0;s<=0;c<=0;state<=1;end
   1:if(enough)begin h<=inc(h);end else state<=2;
   2:if(enough)begin m<=inc(m);end else state<=3;
   3:if(enough)begin s<=inc(s);end else state<=4;
   4:if(enough)begin c<=inc(c);end else begin
    if(select_total)total_bcd<={h,m,s,c};else current_bcd<={h,m,s,c};select_total<=!select_total;state<=0;
   end
   default:state<=0;
  endcase
  end
 end
endmodule
