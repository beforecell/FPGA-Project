// Coarse, persistent 64x48 heat map. Caller supplies floor(source_x/10),
// floor(source_y/10) as cell_index={cell_y[5:0],cell_x[5:0]} (0..3071).
// Any pixel order is supported; multiple pixels in one cell take the maximum.
// frame_start requests a complete decay pass. Hold samples until sample_ready.
// Reset scrubs RAM in 3072 clocks; each decay takes 3073 clocks. Query latency
// is one clock; query_valid is suppressed during scrub/decay. Two duplicated
// 3072x8 simple-dual-port memories permit sample RMW + independent display read.
// No RAM reset loop. Consecutive same-cell writes are explicitly forwarded.
module bb_motion_trail #(
    parameter [7:0] DECAY = 8'd24
) (
    input wire clk, rst, frame_start,
    input wire sample_valid,
    input wire [11:0] cell_index,
    input wire [7:0] intensity,
    output wire sample_ready,
    input wire query_en,
    input wire [11:0] query_index,
    output reg query_valid,
    output wire [7:0] heat,
    output wire [23:0] heat_rgb,
    output wire busy
);
    localparam INIT=2'd0, ACTIVE=2'd1, DECAYING=2'd2, DRAIN=2'd3;
    reg [1:0] state;
    reg [11:0] sweep_addr;
    reg pending, pending_decay;
    reg [11:0] pending_addr;
    reg [7:0] pending_intensity;
    wire [7:0] old_heat,display_q;
    reg last_write_valid;
    reg [11:0] last_write_addr;
    reg [7:0] last_write_data;
    wire [7:0] base_heat=last_write_valid && last_write_addr==pending_addr ?
                              last_write_data : old_heat;
    wire [7:0] decayed=base_heat>DECAY ? base_heat-DECAY : 8'd0;
    wire [7:0] write_data=pending_decay ? decayed :
                              (base_heat>pending_intensity ? base_heat : pending_intensity);
    assign busy=state!=ACTIVE;
    assign sample_ready=state==ACTIVE && !frame_start;
    // Black -> blue -> cyan -> yellow -> red, 64 levels per segment.
    wire [7:0] ramp={heat[5:0],2'b00};
    assign heat_rgb=heat==0 ? 24'd0 : heat[7:6]==0 ? {8'd0,8'd0,ramp} :
                    heat[7:6]==1 ? {8'd0,ramp,8'hff} :
                    heat[7:6]==2 ? {ramp,8'hff,8'hff-ramp} :
                                     {8'hff,8'hff-ramp,8'd0};

    wire store_we=state==INIT || pending;
    wire [11:0] store_waddr=state==INIT ? sweep_addr : pending_addr;
    wire [7:0] store_wdata=state==INIT ? 8'd0 : write_data;
    wire update_re=state==DECAYING || (sample_valid && sample_ready && cell_index<3072);
    wire [11:0] update_addr=state==DECAYING ? sweep_addr : cell_index;
    wire query_accept=query_en && state==ACTIVE && !frame_start && query_index<3072;
    bb_trail_ram3k update_store(clk,store_we,store_waddr,store_wdata,update_re,update_addr,old_heat);
    bb_trail_ram3k display_store(clk,store_we,store_waddr,store_wdata,query_accept,query_index,display_q);
    reg query_forward;
    reg [7:0] query_forward_data;
    assign heat=!query_valid ? 8'd0 : query_forward ? query_forward_data : display_q;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state<=INIT; sweep_addr<=0; pending<=0; pending_decay<=0;
            pending_addr<=0; pending_intensity<=0; last_write_valid<=0;
            last_write_addr<=0; last_write_data<=0; query_valid<=0;
            query_forward<=0;query_forward_data<=0;
        end else begin
            query_valid<=query_accept;
            query_forward<=pending && pending_addr==query_index;
            query_forward_data<=write_data;
            pending<=0;
            last_write_valid<=pending && state!=INIT;
            if (pending && state!=INIT) begin
                last_write_addr<=pending_addr; last_write_data<=write_data;
            end
            case (state)
                INIT: begin
                    if (sweep_addr==3071) begin state<=ACTIVE; sweep_addr<=0; end
                    else sweep_addr<=sweep_addr+1'b1;
                end
                ACTIVE: begin
                    if (frame_start) begin state<=DECAYING; sweep_addr<=0; end
                    else if (sample_valid && cell_index<3072) begin
                        pending<=1; pending_decay<=0; pending_addr<=cell_index;
                        pending_intensity<=intensity;
                    end
                end
                DECAYING: begin
                    pending<=1; pending_decay<=1; pending_addr<=sweep_addr;
                    pending_intensity<=0;
                    if (sweep_addr==3071) state<=DRAIN;
                    else sweep_addr<=sweep_addr+1'b1;
                end
                DRAIN: state<=ACTIVE;
            endcase
        end
    end
endmodule

// Explicit synchronous 3072x8 storage: exactly three 1024x8 ERAM9K macros.
// Address bank is registered alongside each read so all RAM outputs still
// have exactly one clock latency. No reset/initialization of RAM contents;
// parent scrub supplies writes. Collision values are bypassed by the parent.
module bb_trail_ram3k (
    input wire clk,we,input wire [11:0] waddr,input wire [7:0] wdata,
    input wire re,input wire [11:0] raddr,output wire [7:0] q
);
`ifdef __ICARUS__
    reg [7:0] memory[0:3071];
    reg [7:0] read_q;
    always @(posedge clk)begin
        if(we)memory[waddr]<=wdata;
        if(re)read_q<=memory[raddr];
    end
    assign q=read_q;
`else
    wire [7:0] bank_q[0:2];
    reg [1:0] read_bank;
    always @(posedge clk)if(re)read_bank<=raddr[11:10];
    genvar b;
    generate for(b=0;b<3;b=b+1)begin:bank
        EG_LOGIC_BRAM #(
            .DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),
            .DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),
            .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
            .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),
            .IMPLEMENT("9K")
        ) storage(
            .clka(clk),.cea(1'b1),.wea(we && waddr[11:10]==b),.rsta(1'b0),.ocea(1'b0),
            .dia(wdata),.addra(waddr[9:0]),.bea(1'b1),.doa(),
            .clkb(clk),.ceb(re && raddr[11:10]==b),.web(1'b0),.rstb(1'b0),.oceb(1'b1),
            .dib(8'd0),.addrb(raddr[9:0]),.beb(1'b1),.dob(bank_q[b]));
    end endgenerate
    assign q=read_bank==0 ? bank_q[0] : read_bank==1 ? bank_q[1] : bank_q[2];
`endif
endmodule
