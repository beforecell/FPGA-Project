// Reuse elapsed/total formatter;mixed-radix BCD division by two needs only
// small digit carries,no third32-bit formatter or duplicate snapshot bank.
module alpha_time_triplet(input clk,rst,input[31:0]current_ms,total_ms,
 output[31:0]current_bcd,total_bcd,half_bcd);
 alpha_time_dual shared(clk,rst,current_ms,total_ms,current_bcd,total_bcd);
 wire[3:0]ht={1'b0,total_bcd[31:29]};
 wire[3:0]hu={1'b0,total_bcd[27:25]}+(total_bcd[28]?4'd5:4'd0);
 wire[3:0]mt={1'b0,total_bcd[23:21]}+(total_bcd[24]?4'd3:4'd0);
 wire[3:0]mu={1'b0,total_bcd[19:17]}+(total_bcd[20]?4'd5:4'd0);
 wire[3:0]st={1'b0,total_bcd[15:13]}+(total_bcd[16]?4'd3:4'd0);
 wire[3:0]su={1'b0,total_bcd[11:9]}+(total_bcd[12]?4'd5:4'd0);
 wire[3:0]ct={1'b0,total_bcd[7:5]}+(total_bcd[8]?4'd5:4'd0);
 wire[3:0]cu={1'b0,total_bcd[3:1]}+(total_bcd[4]?4'd5:4'd0);
 assign half_bcd={ht,hu,mt,mu,st,su,ct,cu};
endmodule
