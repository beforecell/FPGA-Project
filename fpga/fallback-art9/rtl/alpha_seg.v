module alpha_seg(input clk,rst,input[31:0]time_bcd,input fullscreen,input[1:0]view,
 input[3:0]box_count,output reg[7:0]sel,data);
 reg[15:0]scan;reg[2:0]digit;reg[3:0]d;reg blank,point;
 // Sequential decimal division avoids eight combinational 32-bit dividers.
 reg[31:0]working;reg[31:0]bcd;reg[5:0]step;reg converting;
 wire[31:0]formatted=time_bcd;
 reg[31:0]shown;reg[31:0]time_snapshot;integer k;
 reg[31:0]adj;
 always @*begin adj=bcd;for(k=0;k<8;k=k+1)if(bcd[k*4+:4]>=5)adj[k*4+:4]=bcd[k*4+:4]+3;end
 always @(posedge clk)begin
  if(rst)begin scan<=0;digit<=0;sel<=255;data<=255;working<=0;bcd<=0;step<=0;converting<=0;shown<=0;time_snapshot<=0;end
  else begin
   scan<=scan+1'b1;
   shown<=formatted;
   if(scan==0)begin digit<=digit+1'b1;sel<=~(8'b1<<digit);
    if(fullscreen&&view==3)begin sel<=255;data<=255;end
    else begin
     if(fullscreen&&view==2)begin d<=box_count;blank<=digit!=0;point<=0;end
     else if(fullscreen)begin d<=shown[digit*4+:4];blank<=0;point<=digit==2;end
     else begin d<=shown[(digit+1'b1)*4+:4];blank<=digit==7;point<=digit==1;end
    end
   end
   if(scan==1&&!(fullscreen&&view==3))begin
    case(d)0:data<=8'hc0;1:data<=8'hf9;2:data<=8'ha4;3:data<=8'hb0;4:data<=8'h99;5:data<=8'h92;6:data<=8'h82;7:data<=8'hf8;8:data<=8'h80;9:data<=8'h90;default:data<=255;endcase
    if(blank)data<=255;else if(point)begin
     case(d)0:data<=8'h40;1:data<=8'h79;2:data<=8'h24;3:data<=8'h30;4:data<=8'h19;5:data<=8'h12;6:data<=8'h02;7:data<=8'h78;8:data<=8'h00;9:data<=8'h10;default:data<=127;endcase
    end
   end
  end
 end
endmodule
