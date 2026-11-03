// Atomically freezes each entire 80-byte BBSTAT05 telemetry packet.
module bb_status_tx #(
    parameter integer CLK_HZ=100000000
)(
    input wire clk,input wire rst,input wire force_send,
    input wire [31:0] frame_id,input wire [31:0] energy,input wire [31:0] crc32,
    input wire [15:0] rate_q8_8,input wire [7:0] flags,input wire [7:0] threshold,
    input wire [7:0] gamma,input wire [7:0] error,input wire [15:0] cache_ready,
    input wire [31:0] locked_event_frame,
    input wire [15:0] media_fps,new_fps,hdmi_fps,frame_count,
    input wire [31:0] timestamp_ms,underflows,crc_errors,late_count,display_updates,sd_bps,transport_errors,detector_skips,crc_frame_id,
    output wire [7:0] tx_data,output wire tx_valid,input wire tx_ready
);
    function integer bits_for;
        input integer n;integer v;
        begin v=n-1;bits_for=0;while(v>0)begin bits_for=bits_for+1;v=v>>1;end
              if(bits_for<1)bits_for=1;end
    endfunction
    localparam integer PERIOD=CLK_HZ/2;
    reg [bits_for(PERIOD)-1:0] period_count;
    reg pending,sending;
    reg [6:0] byte_index;
    reg [639:0] packet;
    wire periodic_tick=period_count==PERIOD-1;
    assign tx_data=packet[7:0];
    assign tx_valid=sending;
    always @(posedge clk)begin
        if(rst)begin period_count<=0;pending<=0;sending<=0;byte_index<=0;packet<=0;end
        else begin
            if(periodic_tick)period_count<=0;else period_count<=period_count+1'b1;
            if(force_send || periodic_tick)pending<=1;
            if(!sending && (pending || force_send || periodic_tick))begin
                packet<={crc_frame_id,detector_skips,transport_errors,sd_bps,display_updates,late_count,crc_errors,underflows,32'd0,timestamp_ms,frame_count,hdmi_fps,new_fps,media_fps,locked_event_frame,cache_ready,error,gamma,threshold,flags,
                         rate_q8_8,crc32,energy,frame_id,64'h3530544154534242};
                byte_index<=0;sending<=1;pending<=0;
            end else if(sending && tx_ready)begin
                if(byte_index==79)sending<=0;
                else begin packet<={8'h00,packet[639:8]};byte_index<=byte_index+1'b1;end
            end
        end
    end
endmodule
