module tb;reg clk=0;always #5 clk=~clk;reg rst=1;reg[31:0]cur=0,total=0;wire[31:0]a,b,c;
alpha_time_triplet dut(clk,rst,cur,total,a,b,c);task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
initial begin tick(5);rst=0;cur=0;total=6000;tick(5000);if(a!==32'h00000000||b!==32'h00000600||c!==32'h00000300)$fatal(1,"BCD time mismatch");
cur=61001;total=125099;tick(5000);if(a!==32'h00010100||b!==32'h00020509||c!==32'h00010254)$fatal(1,"BCD time mismatch");
cur=3599999;total=3600010;tick(5000);if(a!==32'h00595999||b!==32'h01000001||c!==32'h00300000)$fatal(1,"BCD time mismatch");
cur=99999999;total=100000000;tick(5000);if(a!==32'h27463999||b!==32'h27464000||c!==32'h13532000)$fatal(1,"BCD time mismatch"); $display("PASS shared elapsed,total,half-total time formatter;seconds/minutes/hours/centisecond boundaries");$finish;end endmodule