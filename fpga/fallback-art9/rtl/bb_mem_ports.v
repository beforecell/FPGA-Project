// Original three-client SDRAM application-bus arbiter. Word addresses, 32 bits.
// Requests are toggles with stable payload until acknowledgement; one write
// job and one paired-read job may coexist. Done toggles echo the accepted token.
// Bounded 128-word bursts. Read owner stays fixed until all 10-cycle responses
// drain. Writes are explicitly pipelined FIFO -> registered AW/address/data,
// then flushed >=10 clocks before a read or write job completion is published.
module bb_mem_ports #(
    parameter integer MAX_BURST=128,
    parameter integer READ_LATENCY=10,
    parameter integer WRITE_FLUSH=10,
    parameter integer LOW_WATERMARK=128
) (
    input wire mem_clk,src_clk,vid_clk,rst_mem,rst_src,rst_vid,
    input wire Sdr_init_done,Sdr_init_ref_vld,Sdr_busy,Sdr_rd_en,
    input wire [31:0] Sdr_rd_dout,
    output reg App_wr_en,
    output reg [20:0] App_wr_addr,
    output reg [31:0] App_wr_din,
    output wire [3:0] App_wr_dm,
    output reg App_rd_en,
    output reg [20:0] App_rd_addr,
    input wire wr_req_toggle,
    input wire [20:0] wr_base,
    input wire [19:0] wr_len,
    output reg wr_ack_toggle,wr_done_toggle,
    input wire [31:0] wr_data,
    input wire wr_valid,
    output wire wr_ready,
    input wire rd_req_toggle,
    input wire [20:0] cur_base,hist_base,
    input wire [9:0] rd_words,
    input wire history_enable,
    output reg rd_ack_toggle,rd_done_toggle,
    input wire cur_pop,hist_pop,
    output wire [31:0] cur_data,hist_data,
    output wire cur_valid,cur_empty,hist_valid,hist_empty,
    output reg wr_overflow,
    output reg mem_fault
);
    localparam IDLE=3'd0,W_POP=3'd1,W_DRAIN=3'd2,W_FLUSH=3'd3,
               R_ISSUE=3'd4,R_DRAIN=3'd5;
    reg [2:0] state;
    reg w_active,r_active,w_token,r_token;
    reg [20:0] w_next_addr,c_next_addr,h_next_addr;
    reg [19:0] w_remaining;
    reg [9:0] c_remaining,h_remaining,c_returns,h_returns;
    reg [1:0] owner,round_robin,urgent_run;
    reg [8:0] burst_words,burst_issued;
    reg [8:0] inflight;
    reg [7:0] quiet;
    (* async_reg="true" *) reg [2:0] w_req_sync,r_req_sync;
    (* async_reg="true" *) reg [40:0] w_payload1,w_payload2;
    (* async_reg="true" *) reg [52:0] r_payload1,r_payload2;
    wire [40:0] w_payload={wr_base,wr_len};
    wire [52:0] r_payload={history_enable,rd_words,cur_base,hist_base};
    always @(posedge mem_clk or posedge rst_mem) begin
        if(rst_mem) begin
            w_req_sync<=0;r_req_sync<=0;
            w_payload1<=0;w_payload2<=0;r_payload1<=0;r_payload2<=0;
        end else begin
            w_req_sync<={w_req_sync[1:0],wr_req_toggle};
            r_req_sync<={r_req_sync[1:0],rd_req_toggle};
            w_payload1<=w_payload;w_payload2<=w_payload1;
            r_payload1<=r_payload;r_payload2<=r_payload1;
        end
    end

    wire w_full,w_empty,w_fifo_valid;
    wire [10:0] w_src_count,w_count,c_count,h_count,c_vid_count,h_vid_count;
    wire [31:0] w_fifo_data;
    wire w_pop=state==W_POP && burst_issued<burst_words && !w_empty;
    wire c_full,h_full;
    // At31.25MHz with the board's180-degree SDRAM clock, the physical
    // read-data bus leads Sdr_rd_en by one application clock (APUG011,
    // section7 item6). Keep the valid/owner accounting unchanged and align
    // the data to it. The earlier ideal model incorrectly advanced both
    // data and valid together and could not expose this board condition.
    reg [31:0] sdr_read_data_d1;
    always @(posedge mem_clk) sdr_read_data_d1<=Sdr_rd_dout;
    wire c_push=Sdr_rd_en && owner==1 && (state==R_ISSUE || state==R_DRAIN);
    wire h_push=Sdr_rd_en && owner==2 && (state==R_ISSUE || state==R_DRAIN);
    assign wr_ready=!w_full && !rst_src;
    assign App_wr_dm=4'b0000;
    bb_async_fifo32k write_fifo(src_clk,rst_src,wr_valid&&wr_ready,wr_data,w_full,w_src_count,
                               mem_clk,rst_mem,w_pop,w_fifo_data,w_fifo_valid,w_empty,w_count);
    bb_async_fifo32k current_fifo(mem_clk,rst_mem,c_push,sdr_read_data_d1,c_full,c_count,
                                 vid_clk,rst_vid,cur_pop,cur_data,cur_valid,cur_empty,c_vid_count);
    bb_async_fifo32k history_fifo(mem_clk,rst_mem,h_push,sdr_read_data_d1,h_full,h_count,
                                 vid_clk,rst_vid,hist_pop,hist_data,hist_valid,hist_empty,h_vid_count);
    // Valid/ready backpressure is legal. Diagnose an actual source protocol
    // violation: dropping/changing the held payload while stalled would lose data.
    reg was_stalled;
    reg [31:0] stalled_data;
    always @(posedge src_clk or posedge rst_src) begin
        if(rst_src) begin wr_overflow<=0;was_stalled<=0;stalled_data<=0;end
        else begin
            if(was_stalled && (!wr_valid || wr_data!=stalled_data)) wr_overflow<=1;
            was_stalled<=wr_valid && !wr_ready;
            if(wr_valid && !wr_ready) stalled_data<=wr_data;
        end
    end

    wire [8:0] w_target=w_remaining>MAX_BURST ? MAX_BURST : w_remaining[8:0];
    wire [8:0] c_target=c_remaining>MAX_BURST ? MAX_BURST : c_remaining[8:0];
    wire [8:0] h_target=h_remaining>MAX_BURST ? MAX_BURST : h_remaining[8:0];
    // FIFO counts already include returned data; inflight reserves data not yet
    // returned. No owner switch occurs with inflight !=0, but keep this budget
    // explicit so a future scheduling change cannot silently overcommit storage.
    wire [11:0] c_reserved={1'b0,c_count}+(owner==1 ? inflight : 9'd0);
    wire [11:0] h_reserved={1'b0,h_count}+(owner==2 ? inflight : 9'd0);
    wire ew=w_active && w_remaining!=0 && w_count>=w_target;
    wire ec=r_active && c_remaining!=0 && c_reserved+c_target<=1024;
    wire eh=r_active && h_remaining!=0 && h_reserved+h_target<=1024;
    wire lc=ec && c_count<LOW_WATERMARK;
    wire lh=eh && h_count<LOW_WATERMARK;
    reg chosen_valid;
    reg [1:0] chosen;
    always @* begin
        chosen_valid=1;chosen=0;
        // At most two urgent display bursts may bypass a ready writer.
        if(ew && urgent_run==2) chosen=0;
        else if(lc || lh) chosen=lh && (!lc || round_robin==2) ? 2 : 1;
        else case(round_robin)
            0: if(ew) chosen=0;else if(ec) chosen=1;else if(eh) chosen=2;else chosen_valid=0;
            1: if(ec) chosen=1;else if(eh) chosen=2;else if(ew) chosen=0;else chosen_valid=0;
            default: if(eh) chosen=2;else if(ew) chosen=0;else if(ec) chosen=1;else chosen_valid=0;
        endcase
    end
    always @(posedge mem_clk or posedge rst_mem) begin
        if(rst_mem) begin
            state<=IDLE;w_active<=0;r_active<=0;w_token<=0;r_token<=0;
            w_next_addr<=0;c_next_addr<=0;h_next_addr<=0;w_remaining<=0;
            c_remaining<=0;h_remaining<=0;c_returns<=0;h_returns<=0;
            owner<=0;round_robin<=0;urgent_run<=0;burst_words<=0;burst_issued<=0;
            inflight<=0;quiet<=0;wr_ack_toggle<=0;wr_done_toggle<=0;
            rd_ack_toggle<=0;rd_done_toggle<=0;App_wr_en<=0;App_wr_addr<=0;
            App_wr_din<=0;App_rd_en<=0;App_rd_addr<=0;mem_fault<=0;
        end else begin
            App_wr_en<=0;App_rd_en<=0;
            // Capture FIFO data one clock after pop. The bus register holds
            // address/data/en coherently until the following SDRAM sampling edge.
            if(w_fifo_valid) begin
                App_wr_en<=1;App_wr_addr<=w_next_addr;App_wr_din<=w_fifo_data;
                w_next_addr<=w_next_addr+1'b1;
            end
            if(App_wr_en) begin
                if(w_remaining==0) mem_fault<=1;
                else w_remaining<=w_remaining-1'b1;
            end
            case({App_rd_en,Sdr_rd_en})
                2'b10: inflight<=inflight+1'b1;
                2'b01: begin
                    if(inflight==0) mem_fault<=1;
                    else inflight<=inflight-1'b1;
                end
                default: inflight<=inflight;
            endcase
            if(Sdr_rd_en) begin
                if(c_push) begin
                    if(c_returns==0 || c_full) mem_fault<=1;
                    else c_returns<=c_returns-1'b1;
                end else if(h_push) begin
                    if(h_returns==0 || h_full) mem_fault<=1;
                    else h_returns<=h_returns-1'b1;
                end else mem_fault<=1;
            end
            if(App_rd_en) begin
                if(owner==1) begin
                    if(c_remaining==0) mem_fault<=1;
                    else c_remaining<=c_remaining-1'b1;
                end else if(owner==2) begin
                    if(h_remaining==0) mem_fault<=1;
                    else h_remaining<=h_remaining-1'b1;
                end else mem_fault<=1;
            end
            if(App_wr_en && App_rd_en) mem_fault<=1;

            if(!w_active && state==IDLE && Sdr_init_done && w_req_sync[2]!=wr_ack_toggle) begin
                wr_ack_toggle<=w_req_sync[2];w_token<=w_req_sync[2];
                w_next_addr<=w_payload2[40:20];w_remaining<=w_payload2[19:0];
                w_active<=w_payload2[19:0]!=0;
                if(w_payload2[19:0]==0) wr_done_toggle<=w_req_sync[2];
            end
            if(!r_active && Sdr_init_done && r_req_sync[2]!=rd_ack_toggle) begin
                rd_ack_toggle<=r_req_sync[2];r_token<=r_req_sync[2];
                c_next_addr<=r_payload2[41:21];h_next_addr<=r_payload2[20:0];
                c_remaining<=r_payload2[51:42];c_returns<=r_payload2[51:42];
                h_remaining<=r_payload2[52] ? r_payload2[51:42] : 10'd0;
                h_returns<=r_payload2[52] ? r_payload2[51:42] : 10'd0;
                r_active<=r_payload2[51:42]!=0;
                if(r_payload2[51:42]==0) rd_done_toggle<=r_req_sync[2];
            end
            case(state)
                IDLE: begin
                    if(r_active && c_returns==0 && h_returns==0 && c_remaining==0 && h_remaining==0 && inflight==0)
                        begin r_active<=0;rd_done_toggle<=r_token;end
                    if(chosen_valid && Sdr_init_done && !Sdr_init_ref_vld && !Sdr_busy) begin
                        owner<=chosen;burst_issued<=0;quiet<=0;
                        round_robin<=chosen==2 ? 0 : chosen+1'b1;
                        if(chosen==0) begin
                            state<=W_POP;burst_words<=w_target;urgent_run<=0;
                        end else begin
                            state<=R_ISSUE;burst_words<=chosen==1 ? c_target : h_target;
                            if(urgent_run<2) urgent_run<=urgent_run+1'b1;
                        end
                    end
                end
                W_POP: if(w_pop) begin
                    burst_issued<=burst_issued+1'b1;
                    if(burst_issued+1'b1==burst_words) state<=W_DRAIN;
                end
                W_DRAIN: if(!w_fifo_valid && !App_wr_en) begin state<=W_FLUSH;quiet<=0;end
                W_FLUSH: begin
                    if(quiet>=WRITE_FLUSH-1) begin
                        state<=IDLE;
                        if(w_remaining==0) begin w_active<=0;wr_done_toggle<=w_token;end
                    end else quiet<=quiet+1'b1;
                end
                R_ISSUE: begin
                    if(burst_issued<burst_words) begin
                        App_rd_en<=1;burst_issued<=burst_issued+1'b1;
                        if(owner==1) begin App_rd_addr<=c_next_addr;c_next_addr<=c_next_addr+1'b1;end
                        else begin App_rd_addr<=h_next_addr;h_next_addr<=h_next_addr+1'b1;end
                    end else begin state<=R_DRAIN;quiet<=0;end
                end
                R_DRAIN: begin
                    if(App_rd_en) quiet<=0;
                    else if(quiet<READ_LATENCY) quiet<=quiet+1'b1;
                    if(inflight==0 && !App_rd_en && !Sdr_rd_en && quiet>=READ_LATENCY) state<=IDLE;
                end
                default: begin state<=IDLE;mem_fault<=1;end
            endcase
        end
    end
endmodule
