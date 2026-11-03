module top(input wire clk,input wire rst_n,input wire uart_rx,output wire uart_tx,
 output wire sd_dclk,inout wire sd_cmd,inout wire [3:0] sd_dat,output wire [3:0] led);
 reg [6:0] boot=0;reg [1:0] reset_sync=0;
 always @(posedge clk)begin if(boot!=127)boot<=boot+1'b1;reset_sync<={reset_sync[0],rst_n};end
 wire rst=boot!=127 || !reset_sync[1];
 wire [7:0] rxd,txd;wire rxv,txv,txr;
 bb_uart8n1 #(.CLK_HZ(50000000),.BAUD(1000000)) serial(clk,rst,uart_rx,rxd,rxv,txd,txv,txr,uart_tx);
 wire sd_start,sd_write,initialized,busy,done,valid,armed,active,soft_reset;
 wire [31:0] lba,dropped,debug1,debug2;
 wire [127:0] cid,csd;wire [63:0] sectors;
 wire [3:0] error;wire [7:0] data,wrdata;wire [8:0] wraddr;
 tf_bridge_core core(clk,rst,rxd,rxv,txd,txv,txr,sd_start,sd_write,lba,
 initialized,busy,done,error,cid,csd,sectors,data,valid,wraddr,wrdata,soft_reset,armed,active,dropped,debug1,debug2);
 sd_maint4 sd(.clk(clk),.rst(rst|soft_reset),.start(sd_start),.lba(lba),.blocks(32'd1),
 .write_op(sd_write),.write_addr(wraddr),.write_data(wrdata),.cid(cid),.csd(csd),.sector_count(sectors),
 .initialized(initialized),.busy(busy),.done(done),.error(error),.data(data),.valid(valid),.ready(1'b1),
 .debug_status(debug1),.debug_data(debug2),.sd_clk(sd_dclk),.sd_cmd(sd_cmd),.sd_dat(sd_dat));
 assign led={error!=0,armed,active,initialized};
endmodule
