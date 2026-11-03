// Small bounded subtractor sequencer, no variable divider in a pixel path.
module alpha_time_format(input clk,rst,input[31:0]ms,output reg[31:0]bcd);
 reg[31:0]last,rem;reg[2:0]state;reg[7:0]h,m,s,c;
 function[7:0]inc;input[7:0]v;begin inc=v[3:0]==9 ? {v[7:4]+4'd1,4'd0}:v+1'b1;end endfunction
 always @(posedge clk)begin
  if(rst)begin last<=32'hffffffff;rem<=0;state<=0;h<=0;m<=0;s<=0;c<=0;bcd<=0;end
  else case(state)
   0:if(ms!=last)begin last<=ms;rem<=ms;h<=0;m<=0;s<=0;c<=0;state<=1;end
   1:if(rem>=3600000)begin rem<=rem-3600000;h<=inc(h);end else state<=2;
   2:if(rem>=60000)begin rem<=rem-60000;m<=inc(m);end else state<=3;
   3:if(rem>=1000)begin rem<=rem-1000;s<=inc(s);end else state<=4;
   4:if(rem>=10)begin rem<=rem-10;c<=inc(c);end else begin bcd<={h,m,s,c};state<=0;end
   default:state<=0;
  endcase
 end
endmodule

module alpha_bcd16(input clk,rst,input[15:0]binary,output reg[19:0]bcd);
 reg[15:0]last,work;reg[19:0]temp,adjusted;reg[4:0]step;reg busy;integer i;
 always @*begin adjusted=temp;for(i=0;i<5;i=i+1)if(temp[i*4+:4]>=5)adjusted[i*4+:4]=temp[i*4+:4]+3;end
 always @(posedge clk)begin
  if(rst)begin bcd<=0;last<=65535;work<=0;temp<=0;step<=0;busy<=0;end
  else if(!busy)begin if(binary!=last)begin last<=binary;work<=binary;temp<=0;step<=0;busy<=1;end end
  else begin temp<={adjusted[18:0],work[15]};work<={work[14:0],1'b0};step<=step+1'b1;if(step==15)begin bcd<={adjusted[18:0],work[15]};busy<=0;end end
 end
endmodule
