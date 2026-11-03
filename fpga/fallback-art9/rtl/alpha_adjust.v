// SW4-only adjustment context. Registers survive media changes, reset on reload.
module alpha_adjust(input clk,rst,active,input[3:0]short_press,long_press,repeat_press,
 input[7:0]volume,output reg[1:0]item,output reg[7:0]exposure,contrast,brightness,
 output reg volume_set,output reg[7:0]volume_value,output reg beep);
 reg was_active;wire up=short_press[2]||long_press[2]||repeat_press[2];
 wire down=short_press[3]||long_press[3]||repeat_press[3];
 wire[7:0]step=(long_press[2]||long_press[3]||repeat_press[2]||repeat_press[3])?8'd4:8'd1;
 wire[7:0]value=item==0?exposure:item==1?contrast:item==2?brightness:volume;
 wire[7:0]next_value=up?(value>=100-step?8'd100:value+step):(value<=step?8'd0:value-step);
 always @(posedge clk)begin
  if(rst)begin was_active<=0;item<=0;exposure<=50;contrast<=50;brightness<=50;volume_set<=0;volume_value<=20;beep<=0;end
  else begin
   was_active<=active;volume_set<=0;beep<=0;
   if(active&&!was_active)begin item<=0;beep<=1;end
   else if(active)begin
    if(short_press[0])begin item<=item+1'b1;beep<=1;end
    else if(up^down)begin
     if(next_value!=value)begin
      beep<=1;
      case(item)0:exposure<=next_value;1:contrast<=next_value;2:brightness<=next_value;3:begin volume_set<=1;volume_value<=next_value;end endcase
     end
    end
   end
  end
 end
endmodule
