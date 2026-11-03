// Four samples are inside one4x2 compressed block. Average BEFORE decimation;
// (sum+2)>>2 is an explicit half-up integer box filter, not nearest sampling.
module bb48_area_pixel(input [31:0] endpoints,input [15:0] selectors,
 input x_pair,output [23:0] rgb);
 wire [23:0] a,b,c,d;wire [15:0] ua,ub,uc,ud;
 bc1_block_pixel p0(endpoints,{16'd0,selectors},{x_pair,1'b0},2'd0,ua,a);
 bc1_block_pixel p1(endpoints,{16'd0,selectors},{x_pair,1'b1},2'd0,ub,b);
 bc1_block_pixel p2(endpoints,{16'd0,selectors},{x_pair,1'b0},2'd1,uc,c);
 bc1_block_pixel p3(endpoints,{16'd0,selectors},{x_pair,1'b1},2'd1,ud,d);
 wire [9:0] sr={2'b0,a[23:16]}+{2'b0,b[23:16]}+{2'b0,c[23:16]}+{2'b0,d[23:16]}+10'd2;
 wire [9:0] sg={2'b0,a[15:8]}+{2'b0,b[15:8]}+{2'b0,c[15:8]}+{2'b0,d[15:8]}+10'd2;
 wire [9:0] sb={2'b0,a[7:0]}+{2'b0,b[7:0]}+{2'b0,c[7:0]}+{2'b0,d[7:0]}+10'd2;
 assign rgb={sr[9:2],sg[9:2],sb[9:2]};
endmodule
