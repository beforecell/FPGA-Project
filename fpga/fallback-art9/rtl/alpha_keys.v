// Physical order: KEY1=A2, KEY2=B2, KEY3=B1, KEY4=C1.
// Events occur on release, unless the long action already fired.
module alpha_keys #(parameter CLK_HZ=100000000,DEBOUNCE_MS=20,LONG_MS=1000)(
 input clk,rst,input[3:0]key_n,output reg[3:0]short_press,long_press,input[3:0]repeat_mask,output reg[3:0]repeat_press,input[5:0]context_token);
 (* async_reg="true" *)reg[3:0]meta,sync;
 localparam DB=CLK_HZ/1000*DEBOUNCE_MS,HOLD=CLK_HZ/1000*LONG_MS;
 localparam DBW=$clog2(DB+1),HW=$clog2(HOLD+1);
 reg[$clog2(CLK_HZ/4+1)-1:0]repeater[0:3];
 reg[3:0]blocked,previous_repeat_mask;reg[5:0]previous_context;
 reg[3:0]stable,fired;reg[DBW-1:0]deb[0:3];reg[HW-1:0]held[0:3];integer i;
 always @(posedge clk)begin
  if(rst)begin meta<=15;sync<=15;stable<=15;fired<=0;short_press<=0;long_press<=0;
   repeat_press<=0;blocked<=0;previous_repeat_mask<=0;previous_context<=0;for(i=0;i<4;i=i+1)begin deb[i]<=0;held[i]<=0;repeater[i]<=0;end
  end else begin
   meta<=key_n;sync<=meta;previous_repeat_mask<=repeat_mask;previous_context<=context_token;short_press<=0;long_press<=0;repeat_press<=0;
   for(i=0;i<4;i=i+1)begin
    if(sync[i]==stable[i])deb[i]<=0;
    else if(deb[i]==DB-1)begin
     stable[i]<=sync[i];deb[i]<=0;
     if(sync[i])begin if(!fired[i]&&held[i]<HOLD-1)short_press[i]<=1;else if(!fired[i])long_press[i]<=1;fired[i]<=0;held[i]<=0;end
    end else deb[i]<=deb[i]+1'b1;
    if(!stable[i]&&!fired[i]&&!(sync[i]&&deb[i]==DB-1))begin
     if(held[i]==HOLD-1)begin long_press[i]<=1;fired[i]<=1;end
     else held[i]<=held[i]+1'b1;
    end
    if(stable[i])held[i]<=0;
    if(sync[i]||!repeat_mask[i]||!fired[i])repeater[i]<=0;
    else if(repeater[i]==CLK_HZ/4-1)begin repeat_press[i]<=1;repeater[i]<=0;end else repeater[i]<=repeater[i]+1'b1;
   end
   for(i=0;i<4;i=i+1)begin
    if(sync[i])blocked[i]<=0;
    if(blocked[i])begin short_press[i]<=0;long_press[i]<=0;repeat_press[i]<=0;held[i]<=0;repeater[i]<=0;end
   end
   if(previous_repeat_mask!=repeat_mask||previous_context!=context_token)begin
    blocked<=~sync;fired<=fired|~sync;
    short_press<=0;long_press<=0;repeat_press<=0;
   end
   // Chord owns both buttons from their press; never navigate on its release.
   if(sync==0)begin short_press<=0;long_press<=0;repeat_press<=0;fired<=15;end
  end
 end
endmodule

module alpha_board_reset #(parameter CLK_HZ=50000000)(input clk,input[3:0]chord_n,output reset);
 reg[19:0]por=0;reg[27:0]held=0;reg reset_pulse=0;(* async_reg="true" *)reg[3:0]m=15,s=15;
 always @(posedge clk)begin
  if(!por[19])por<=por+1'b1;
  m<=chord_n;s<=m;reset_pulse<=0;
  if(s==0)begin if(held<CLK_HZ*3)held<=held+1'b1;if(held==CLK_HZ*3-1)reset_pulse<=1;end
  else held<=0;
 end
 assign reset=!por[19]||reset_pulse;
endmodule
