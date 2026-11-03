// 8N1 UART, integer-rounded baud divider; no vendor primitives.
module bb_uart8n1 #(
    parameter integer CLK_HZ=100000000,
    parameter integer BAUD=115200
)(
    input wire clk,input wire rst,input wire rx,
    output reg [7:0] rx_data,output reg rx_valid,
    input wire [7:0] tx_data,input wire tx_valid,output wire tx_ready,
    output reg tx
);
    function integer bits_for;
        input integer n;integer v;
        begin v=n-1;bits_for=0;while(v>0)begin bits_for=bits_for+1;v=v>>1;end
              if(bits_for<1)bits_for=1;end
    endfunction
    localparam integer BIT_CYCLES=(CLK_HZ+BAUD/2)/BAUD;
    localparam integer HALF_CYCLES=BIT_CYCLES/2;
    localparam integer CW=bits_for(BIT_CYCLES);
    reg rx_meta,rx_sync;
    always @(posedge clk)begin
        if(rst)begin rx_meta<=1;rx_sync<=1;end
        else begin rx_meta<=rx;rx_sync<=rx_meta;end
    end
    reg [1:0] rx_state;
    reg [CW-1:0] rx_count;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift;
    localparam RX_IDLE=0,RX_START=1,RX_DATA=2,RX_STOP=3;
    always @(posedge clk)begin
        if(rst)begin
            rx_state<=RX_IDLE;rx_count<=0;rx_bit<=0;rx_shift<=0;
            rx_data<=0;rx_valid<=0;
        end else begin
            rx_valid<=0;
            case(rx_state)
              RX_IDLE:if(!rx_sync)begin rx_count<=HALF_CYCLES-1;rx_state<=RX_START;end
              RX_START:if(rx_count!=0)rx_count<=rx_count-1'b1;
                else if(rx_sync)rx_state<=RX_IDLE;
                else begin rx_count<=BIT_CYCLES-1;rx_bit<=0;rx_state<=RX_DATA;end
              RX_DATA:if(rx_count!=0)rx_count<=rx_count-1'b1;
                else begin
                    rx_shift[rx_bit]<=rx_sync;rx_count<=BIT_CYCLES-1;
                    if(rx_bit==7)rx_state<=RX_STOP;else rx_bit<=rx_bit+1'b1;
                end
              RX_STOP:if(rx_count!=0)rx_count<=rx_count-1'b1;
                else begin
                    // A low stop bit is a framing error: silently discard it.
                    if(rx_sync)begin rx_data<=rx_shift;rx_valid<=1;end
                    rx_state<=RX_IDLE;
                end
              default:rx_state<=RX_IDLE;
            endcase
        end
    end
    reg tx_busy;
    reg [9:0] tx_frame;
    reg [3:0] tx_bit;
    reg [CW-1:0] tx_count;
    assign tx_ready=!tx_busy;
    always @(posedge clk)begin
        if(rst)begin tx<=1;tx_busy<=0;tx_frame<=10'h3ff;tx_bit<=0;tx_count<=0;end
        else if(!tx_busy)begin
            tx<=1;
            if(tx_valid)begin
                tx_frame<={1'b1,tx_data,1'b0};tx<=0;tx_busy<=1;
                tx_bit<=0;tx_count<=BIT_CYCLES-1;
            end
        end else if(tx_count!=0)tx_count<=tx_count-1'b1;
        else if(tx_bit==9)begin tx<=1;tx_busy<=0;end
        else begin
            tx_bit<=tx_bit+1'b1;tx<=tx_frame[tx_bit+1'b1];tx_count<=BIT_CYCLES-1;
        end
    end
endmodule
