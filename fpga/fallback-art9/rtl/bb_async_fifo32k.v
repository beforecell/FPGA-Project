// 1024x32 asynchronous FIFO, one-clock synchronous read (not show-ahead).
// Both sides must be reset together at startup; never reset per job.
// Gray pointers carry 11 bits including wrap; counts are conservative locally.
// Native TD primitive is EG_LOGIC_BRAM with IMPLEMENT="32K" (there is no
// EG_LOGIC_BRAM32K primitive in TD 6.2.1's eagle_macro.v library).
module bb_async_fifo32k (
    input wire wr_clk, wr_rst, wr_en,
    input wire [31:0] wr_data,
    output reg full,
    output wire [10:0] wr_count,
    input wire rd_clk, rd_rst, rd_en,
    output wire [31:0] rd_data,
    output reg rd_valid, empty,
    output wire [10:0] rd_count
);
    reg [10:0] wbin, wgray, rbin, rgray;
    (* async_reg="true" *) reg [10:0] rgray_w1, rgray_w2;
    (* async_reg="true" *) reg [10:0] wgray_r1, wgray_r2;
    wire write_fire=wr_en && !full;
    wire read_fire=rd_en && !empty;
    wire [10:0] wbin_next=wbin+write_fire;
    wire [10:0] rbin_next=rbin+read_fire;
    wire [10:0] wgray_next=(wbin_next>>1)^wbin_next;
    wire [10:0] rgray_next=(rbin_next>>1)^rbin_next;
    function [10:0] gray_bin;
        input [10:0] g;
        integer k;
        begin
            gray_bin[10]=g[10];
            for(k=9;k>=0;k=k-1) gray_bin[k]=gray_bin[k+1]^g[k];
        end
    endfunction
    assign wr_count=wbin-gray_bin(rgray_w2);
    assign rd_count=gray_bin(wgray_r2)-rbin;
    always @(posedge wr_clk or posedge wr_rst) begin
        if(wr_rst) begin wbin<=0;wgray<=0;full<=0;rgray_w1<=0;rgray_w2<=0;end
        else begin
            rgray_w1<=rgray;rgray_w2<=rgray_w1;
            wbin<=wbin_next;wgray<=wgray_next;
            full<=wgray_next=={~rgray_w2[10:9],rgray_w2[8:0]};
        end
    end
    always @(posedge rd_clk or posedge rd_rst) begin
        if(rd_rst) begin rbin<=0;rgray<=0;empty<=1;rd_valid<=0;wgray_r1<=0;wgray_r2<=0;end
        else begin
            wgray_r1<=wgray;wgray_r2<=wgray_r1;
            rbin<=rbin_next;rgray<=rgray_next;
            empty<=rgray_next==wgray_r2;rd_valid<=read_fire;
        end
    end
`ifdef __ICARUS__
    reg [31:0] memory[0:1023];
    reg [31:0] q;
    assign rd_data=q;
    always @(posedge wr_clk) if(write_fire) memory[wbin[9:0]]<=wr_data;
    always @(posedge rd_clk) if(read_fire) q<=memory[rbin[9:0]];
`else
    EG_LOGIC_BRAM #(
        .DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
        .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),
        .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
        .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
        .IMPLEMENT("32K")
    ) storage (
        .clka(wr_clk),.cea(1'b1),.wea(write_fire),.rsta(1'b0),.ocea(1'b0),
        .dia(wr_data),.addra(wbin[9:0]),.bea(1'b1),.doa(),
        .clkb(rd_clk),.ceb(read_fire),.web(1'b0),.rstb(1'b0),.oceb(1'b1),
        .dib(32'd0),.addrb(rbin[9:0]),.beb(1'b1),.dob(rd_data)
    );
`endif
endmodule
