// Explicit synchronous memories. Simulation branch is the same1clock-read
// contract; primitive-bank branch must also be exercised with a contract model.
module bb3_sdp_ram #(parameter WIDTH=9,AW=10,DEPTH=1024,IMPLEMENT="9K")(
 input clk,we,input [AW-1:0] wa,input [WIDTH-1:0] din,
 input re,input [AW-1:0] ra,output [WIDTH-1:0] dout);
`ifdef __ICARUS__
 reg[WIDTH-1:0]mem[0:DEPTH-1];reg[WIDTH-1:0]q;
 always @(posedge clk)begin if(we)mem[wa]<=din;if(re)q<=mem[ra];end
 assign dout=q;
`else
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(WIDTH),.DATA_WIDTH_B(WIDTH),.ADDR_WIDTH_A(AW),.ADDR_WIDTH_B(AW),
 .DATA_DEPTH_A(DEPTH),.DATA_DEPTH_B(DEPTH),.BYTE_ENABLE(0),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
 .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT(IMPLEMENT)) storage(
 .clka(clk),.cea(1'b1),.wea(we),.rsta(1'b0),.ocea(1'b0),.dia(din),.addra(wa),.bea(1'b1),.doa(),
 .clkb(clk),.ceb(re),.web(1'b0),.rstb(1'b0),.oceb(1'b1),.dib({WIDTH{1'b0}}),.addrb(ra),.beb(1'b1),.dob(dout));
`endif
endmodule

// No power-of-two padding at page level:5pages store4800 grayscale cells,
//9pages store8534packed9bit words for a320x240 binary image.
module bb3_paged_ram #(parameter WIDTH=9,PAGES=9)(
 input clk,we,input[13:0]wa,input[WIDTH-1:0]din,
 input re,input[13:0]ra,output[WIDTH-1:0]dout);
 // A falling-edge launch makes write address/data/enable stable for half a
 // pixel period before the RAM rising edge. This preserves the same write
 // edge as the original combinational inputs and gives a real hold margin.
 reg we_half;reg[13:0]wa_half;reg[WIDTH-1:0]din_half;
 always @(negedge clk)begin we_half<=we;wa_half<=wa;din_half<=din;end
 wire[PAGES*WIDTH-1:0]q;reg[3:0]bank;
 always @(posedge clk)if(re)bank<=ra[13:10];
 genvar n;generate for(n=0;n<PAGES;n=n+1)begin:page
  bb3_sdp_ram #(.WIDTH(WIDTH)) ram(clk,we_half&&wa_half[13:10]==n,wa_half[9:0],din_half,re&&ra[13:10]==n,ra[9:0],q[n*WIDTH+:WIDTH]);
 end endgenerate
 assign dout=q[bank*WIDTH+:WIDTH];
endmodule
