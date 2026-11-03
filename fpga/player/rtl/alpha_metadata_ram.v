// Reuse two existing32-bit status ERAMs. Status occupies0..31;bookmarks
// occupy128..207 (the high address bit selects the bank,without an adder).
// Separate write/read arbitration;bookmarks have priority and never stall.
// Status clients hold their commands until granted. One-clock read contract.
module alpha_metadata_ram(input clk,
 input book_we,book_re,input[6:0]book_wa,book_ra,input[15:0]book_din,output[15:0]book_q,
 input status_we,status_re,input[4:0]status_wa,status_ra,input[31:0]status_din,
 output[31:0]status_q,output status_wready,status_rready);
 wire we=book_we||status_we,re=book_re||status_re;
 wire[7:0]wa=book_we?{1'b1,book_wa}:{3'd0,status_wa};
 wire[7:0]ra=book_re?{1'b1,book_ra}:{3'd0,status_ra};
 wire[31:0]q;
 wire[31:0]din=book_we?{16'd0,book_din}:status_din;
 assign status_wready=!book_we;assign status_rready=!book_re;
 assign status_q=q;assign book_q=q[15:0];
 bb3_sdp_ram #(.WIDTH(32),.AW(8),.DEPTH(256)) storage(clk,we,wa,din,re,ra,q);
endmodule
