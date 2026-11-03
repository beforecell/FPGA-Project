// Opaque BC1 4x4 random-access pixel decoder. Color0>color1 is required.
// LE word0={RGB565 color1,RGB565 color0}; word1={16 x 2-bit selector}.
// Integer /3 is floor, after bit-replicated endpoint expansion to RGB888.
// Combinational latency: 0 registers. Register at caller's pixel boundary.
module bc1_block_pixel (
    input wire [31:0] endpoints,
    input wire [31:0] selectors,
    input wire [1:0] x_in_block,
    input wire [1:0] y_in_block,
    output wire [15:0] rgb565,
    output reg [23:0] rgb888
);
    wire [15:0] c0 = endpoints[15:0];
    wire [15:0] c1 = endpoints[31:16];
    wire [7:0] r0 = {c0[15:11],c0[15:13]};
    wire [7:0] g0 = {c0[10:5],c0[10:9]};
    wire [7:0] b0 = {c0[4:0],c0[4:2]};
    wire [7:0] r1 = {c1[15:11],c1[15:13]};
    wire [7:0] g1 = {c1[10:5],c1[10:9]};
    wire [7:0] b1 = {c1[4:0],c1[4:2]};
    wire [4:0] shift = {y_in_block,x_in_block,1'b0};
    wire [1:0] code = (selectors >> shift) & 2'b11;
    // Compute the block palette BEFORE selecting a pixel. Area-filter callers
    // share these selector-independent values across their four pixel queries.
    wire [7:0] r2 = (({2'b0,r0}<<1)+{2'b0,r1})/10'd3;
    wire [7:0] g2 = (({2'b0,g0}<<1)+{2'b0,g1})/10'd3;
    wire [7:0] b2 = (({2'b0,b0}<<1)+{2'b0,b1})/10'd3;
    wire [7:0] r3 = ({2'b0,r0}+({2'b0,r1}<<1))/10'd3;
    wire [7:0] g3 = ({2'b0,g0}+({2'b0,g1}<<1))/10'd3;
    wire [7:0] b3 = ({2'b0,b0}+({2'b0,b1}<<1))/10'd3;
    always @* begin
        case (code)
            2'd0: rgb888 = {r0,g0,b0};
            2'd1: rgb888 = {r1,g1,b1};
            2'd2: rgb888 = {r2,g2,b2};
            default: rgb888 = {r3,g3,b3};
        endcase
    end
    assign rgb565 = {rgb888[23:19],rgb888[15:10],rgb888[7:3]};
endmodule
