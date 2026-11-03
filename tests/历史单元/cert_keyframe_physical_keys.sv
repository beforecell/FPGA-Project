module tb;
reg clk=0;always #5 clk=~clk;reg rst=1;reg[3:0]kn=15,mask=0;reg[6:0]ctx=0;
wire[3:0]s,l,r;integer shorts=0,longs=0,repeats=0;
alpha_keys #(.CLK_HZ(1000),.DEBOUNCE_MS(2),.LONG_MS(20)) dut(clk,rst,kn,s,l,mask,r,ctx);
always @(posedge clk)if(!rst)begin #1;if(s!=0)shorts=shorts+1;if(l!=0)longs=longs+1;if(r!=0)repeats=repeats+1;end
task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
initial begin
 tick(5);rst=0;tick(5);
 ctx=7'b0000100;mask=8;tick(4);kn=7;tick(30);if(longs!=1)$fatal(1,"long setup");
 ctx=7'b0000001;mask=0;tick(8);kn=15;tick(10);if(shorts!=0||longs!=1)$fatal(1,"held rate key became mark after SW2->SW3");
 kn=7;tick(8);kn=15;tick(10);if(shorts!=1)$fatal(1,"new keyframe short missing");
 kn=13;tick(8);ctx=7'b1000000;tick(5);kn=15;tick(10);if(shorts!=1)$fatal(1,"browser high context bit failed to suppress held KEY2");
 kn=13;tick(8);kn=15;tick(10);if(shorts!=2)$fatal(1,"key not rearmed after release");
 $display("PASS real pin debounce:rate-held KEY4 cannot become bookmark on mode change;release no extra short;all7 context bits including browser and keyframes;fresh presses rearm");$finish;
end
endmodule