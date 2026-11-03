module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,ready=0;wire[7:0]data;wire valid;integer i=0,f,cycle=0;reg injected=0;
reg[127:0]keys=128'h20002a00000103050000007800260007;
alpha_status_tx #(.CLK_HZ(100),.KEYFRAME_PROTOCOL(1)) dut(clk,rst,8'hd8,8'd0,8'd6,8'd0,16'd120,16'd30,
32'd4000,32'd192000,32'd0,16'h003f,16'h003c,8'h4f,8'h1f,8'd0,8'd7,8'd8,8'd9,8'd1,8'd0,
32'd4096,32'd17000000,32'd101,16'd256,8'd0,8'h20,32'd96000,data,valid,ready,224'h00323232010000140000002e0000002e0000bb80007700784b545241,keys,,,,,,32'd0,1'b1,1'b1);
always @(negedge clk)begin
 cycle=cycle+1;ready=cycle%7!=0;
 if(i>=92&&!injected&&dut.capturing&&dut.capture_word==10)begin keys[111:104]=43;keys[15:0]=8;injected=1;end
end
always @(posedge clk)if(!rst&&valid&&ready)begin
 $fwrite(f,"%c",data);i=i+1;
 if(i==184)begin $fclose(f);$display("PASS ALPHAST7 92-byte packets,UART backpressure,CRC and generation endpoints for torn bookmark list");$finish;end
end
initial begin f=$fopen("keyframe_status.bin","wb");repeat(5)@(negedge clk);rst=0;end
initial begin #100000;$fatal(1,"status timeout");end
endmodule