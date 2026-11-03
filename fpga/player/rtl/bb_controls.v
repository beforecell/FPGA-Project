// Physical KEY2/KEY3/KEY4 are active-low. UART bytes match UART_PROTOCOL.md.
module bb_controls #(
    parameter integer CLK_HZ=100000000
)(
    input wire clk100,input wire rst,
    input wire key_next,input wire key_prev,input wire key_play,
    input wire [3:0] sw,input wire [7:0] rx_data,input wire rx_valid,
    input wire alarm_sync,input wire [7:0] adc_value,input wire adc_valid,
    input wire media_ready,input wire [15:0] media_fps,
    output reg playing,output reg [15:0] rate_q8_8,
    output reg [7:0] threshold,output reg [1:0] gamma,
    output reg photo_mode,output reg quad_mode,output reg auto_slow,
    output reg adc_enable,output reg [1:0] menu,output reg camera_mode,diagnostic,
    output reg next_press,output reg prev_press,output reg clear_alarm_toggle
);
    // Keep the UART byte local to the control decoder, with valid aligned.
    reg [7:0] cmd_data;reg cmd_valid;
    always @(posedge clk100)begin
        if(rst)begin cmd_data<=0;cmd_valid<=0;end
        else begin cmd_data<=rx_data;cmd_valid<=rx_valid;end
    end
    function integer bits_for;
        input integer n;integer v;
        begin v=n-1;bits_for=0;while(v>0)begin bits_for=bits_for+1;v=v>>1;end
              if(bits_for<1)bits_for=1;end
    endfunction
    function [15:0] rate_up;
        input [15:0] r;input [15:0] step;
        begin rate_up=r>=16'd15360-step?16'd15360:r+step;end
    endfunction
    function [15:0] rate_down;
        input [15:0] r;input [15:0] step;
        begin rate_down=r<=16'd256+step?16'd256:r-step;end
    endfunction
    wire next_short,next_long,prev_short,prev_long,play_short,play_long;
    bb_key_event #(.CLK_HZ(CLK_HZ)) u_key_next(.clk(clk100),.rst(rst),.key_n(key_next),.short_press(next_short),.long_press(next_long));
    bb_key_event #(.CLK_HZ(CLK_HZ)) u_key_prev(.clk(clk100),.rst(rst),.key_n(key_prev),.short_press(prev_short),.long_press(prev_long));
    bb_key_event #(.CLK_HZ(CLK_HZ)) u_key_play(.clk(clk100),.rst(rst),.key_n(key_play),.short_press(play_short),.long_press(play_long));
    reg [3:0] sw_meta,sw_sync;
    reg media_seen,user_rate_set;
    reg alarm_prev,slow_active;
    reg [15:0] saved_rate;
    reg [1:0] uart_state;
    reg [7:0] uart_rate_low;
    localparam integer UART_TIMEOUT=CLK_HZ/10;
    reg [bits_for(UART_TIMEOUT)-1:0] uart_wait;
    wire [15:0] requested_rate={cmd_data,uart_rate_low};
    wire clear_command=cmd_valid && uart_state==0 && cmd_data==8'h72;
    always @(posedge clk100)begin
        if(rst)begin sw_meta<=0;sw_sync<=0;end
        else begin sw_meta<=sw;sw_sync<=sw_meta;end
    end
    always @* begin
        // Physical positions are authoritative; no UART/long-press XOR state.
        quad_mode=1'b0;auto_slow=sw_sync[1];
        camera_mode=sw_sync[2];diagnostic=sw_sync[3];
    end
    always @(posedge clk100)begin
        if(rst)begin
            playing<=1;rate_q8_8<=16'd7680;threshold<=24;gamma<=0;menu<=0;
            next_press<=0;prev_press<=0;clear_alarm_toggle<=0;
            photo_mode<=0;adc_enable<=0;media_seen<=0;user_rate_set<=0;alarm_prev<=0;slow_active<=0;saved_rate<=7680;
            uart_state<=0;uart_rate_low<=0;uart_wait<=0;
        end else begin
            next_press<=0;prev_press<=0;alarm_prev<=alarm_sync;
            // Long actions never also generate a short action on release.
            if(prev_long)menu<=menu==0?2'd1:2'd0;
            if(play_long)begin photo_mode<=!photo_mode;menu<=0;end
            // No hidden speed preset on KEY2 long press.
            if(media_ready&&!media_seen)begin
                media_seen<=1;
                if(!user_rate_set&&media_fps>=1&&media_fps<=60)begin rate_q8_8<=media_fps<<8;saved_rate<=media_fps<<8;end
            end
            if(slow_active&&!auto_slow)begin rate_q8_8<=saved_rate;slow_active<=0;end
            if(next_short)begin
                case(menu)
                  0:begin next_press<=1;playing<=0;end
                  1:threshold<=threshold>=252?8'd252:threshold+8'd4;
                  2:if(gamma!=3)gamma<=gamma+1'b1;
                  3:begin rate_q8_8<=rate_up(rate_q8_8,16'd64);user_rate_set<=1;end
                endcase
            end
            if(prev_short)begin
                case(menu)
                  0:begin prev_press<=1;playing<=0;end
                  1:threshold<=threshold<=4?8'd0:threshold-8'd4;
                  2:if(gamma!=0)gamma<=gamma-1'b1;
                  3:begin rate_q8_8<=rate_down(rate_q8_8,16'd64);user_rate_set<=1;end
                endcase
            end
            if(play_short)begin
                if(menu==0)playing<=!playing;
                else menu<=menu+1'b1;
            end

            // R + uint16LE is a three-byte transaction. Timeout discards a
            // partial transaction without interpreting its payload as commands.
            if(cmd_valid)begin
                uart_wait<=0;
                if(uart_state==1)begin uart_rate_low<=cmd_data;uart_state<=2;end
                else if(uart_state==2)begin
                    if(requested_rate>=256 && requested_rate<=15360)begin rate_q8_8<=requested_rate;user_rate_set<=1;end
                    uart_state<=0;
                end else begin
                    case(cmd_data)
                      8'h52:uart_state<=1;                 // R: precise Q8.8 rate
                      8'h70:playing<=!playing;              // p: toggle
                      8'h50:playing<=1;                     // P: play
                      8'h73:playing<=0;                     // s: pause
                      8'h6e:begin next_press<=1;playing<=0;end
                      8'h62:begin prev_press<=1;playing<=0;end
                      8'h69:begin photo_mode<=1;menu<=0;end // i: explicit image album
                      8'h76:begin photo_mode<=0;menu<=0;end // v: same video progress
                      8'h41:adc_enable<=!adc_enable;       // A: external ADC opt-in
                      8'h2b:begin rate_q8_8<=rate_up(rate_q8_8,16'd256);user_rate_set<=1;end
                      8'h2d:begin rate_q8_8<=rate_down(rate_q8_8,16'd256);user_rate_set<=1;end
                      8'h5b:threshold<=threshold<=4?8'd0:threshold-8'd4;
                      8'h5d:threshold<=threshold>=252?8'd252:threshold+8'd4;
                      8'h67:gamma<=gamma+1'b1;
                      8'h72:begin
                          clear_alarm_toggle<=!clear_alarm_toggle;
                          if(slow_active)rate_q8_8<=saved_rate;
                          slow_active<=0;
                      end
                      default:begin end
                    endcase
                end
            end else if(uart_state!=0)begin
                if(uart_wait==UART_TIMEOUT-1)begin uart_state<=0;uart_wait<=0;end
                else uart_wait<=uart_wait+1'b1;
            end
            // ADC is an explicit SW4-selected owner of T; gamma is independent.
            if(adc_enable && adc_valid)threshold<=adc_value&8'hfc;
            // A new event has priority over simultaneous ordinary rate changes.
            // Clearing the event has priority over this automatic trigger.
            if(alarm_sync && !alarm_prev && auto_slow && !slow_active && !clear_command)begin
                saved_rate<=rate_q8_8;rate_q8_8<=16'd512;slow_active<=1;
            end
        end
    end
endmodule

module bb_key_event #(
    parameter integer CLK_HZ=100000000,
    parameter integer DEBOUNCE_MS=20,
    parameter integer HOLD_MS=800
)(input wire clk,input wire rst,input wire key_n,
  output reg short_press,output reg long_press);
    function integer bits_for;
        input integer n;integer v;
        begin v=n-1;bits_for=0;while(v>0)begin bits_for=bits_for+1;v=v>>1;end
              if(bits_for<1)bits_for=1;end
    endfunction
    localparam integer DB_CYCLES=(CLK_HZ/1000)*DEBOUNCE_MS;
    localparam integer LONG_CYCLES=(CLK_HZ/1000)*HOLD_MS;
    reg key_meta,key_sync,stable,previous_stable,long_fired;
    reg [bits_for(DB_CYCLES)-1:0] debounce_count;
    reg [bits_for(LONG_CYCLES)-1:0] hold_count;
    always @(posedge clk)begin
        if(rst)begin
            key_meta<=1;key_sync<=1;stable<=1;previous_stable<=1;
            long_fired<=0;debounce_count<=0;hold_count<=0;short_press<=0;long_press<=0;
        end else begin
            key_meta<=key_n;key_sync<=key_meta;previous_stable<=stable;
            short_press<=0;long_press<=0;
            if(key_sync==stable)debounce_count<=0;
            else if(debounce_count==DB_CYCLES-1)begin stable<=key_sync;debounce_count<=0;end
            else debounce_count<=debounce_count+1'b1;
            if(!stable)begin
                if(previous_stable)begin hold_count<=0;long_fired<=0;end
                else if(!long_fired)begin
                    if(hold_count==LONG_CYCLES-1)begin long_press<=1;long_fired<=1;end
                    else hold_count<=hold_count+1'b1;
                end
            end else if(!previous_stable)begin
                if(!long_fired)short_press<=1;
                long_fired<=0;hold_count<=0;
            end
        end
    end
endmodule
