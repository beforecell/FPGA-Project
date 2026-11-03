// Integer piecewise gamma-like lift, exact PC golden in vision_golden.py.
// No multiplier, no statistics feedback. This is not CLAHE. Black stays black.
// strength 0: identity, 1: mild, 2/3: strong. One pixel clock latency including
// hs/vs/de; sampled configuration affects the pixel sampled on that same edge.
module bb_night_gamma (
    input wire clk, rst, hs, vs, de,
    input wire [23:0] rgb,
    input wire [1:0] strength,
    output reg ohs, ovs, ode,
    output reg [23:0] out_rgb
);
    function [7:0] lift;
        input [7:0] p;
        input [1:0] level;
        reg [8:0] v;
        begin
            if (level==0) v={1'b0,p};
            else if (level==1) begin
                if (p<32) v={1'b0,p}+{1'b0,p};
                else if (p<96) v={1'b0,p}+9'd32;
                else if (p<192) v=9'd128+(({1'b0,p}-9'd96)*3 >> 2);
                else v=9'd200+(({1'b0,p}-9'd192)*7 >> 3);
            end else begin
                if (p<32) v={1'b0,p}+{1'b0,p}+{1'b0,p};
                else if (p<96) v=9'd96+({1'b0,p}-9'd32);
                else if (p<192) v=9'd160+(({1'b0,p}-9'd96)*5 >> 3);
                else v=9'd220+(({1'b0,p}-9'd192)*5 >> 3);
            end
            lift=v>255 ? 8'd255 : v[7:0];
        end
    endfunction
    always @(posedge clk or posedge rst) begin
        if (rst) begin ohs<=0; ovs<=0; ode<=0; out_rgb<=0; end
        else begin
            ohs<=hs; ovs<=vs; ode<=de;
            out_rgb<={lift(rgb[23:16],strength),lift(rgb[15:8],strength),lift(rgb[7:0],strength)};
        end
    end
endmodule
