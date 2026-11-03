// Physical SEL0 is the leftmost digit. Both SEL and segment pads are low-active.
module bb_seg8_frame #(
    parameter integer CLK_HZ=50000000,
    parameter integer DIGIT_HZ=1000,
    parameter integer BLINK_HZ=2
)(
    input wire clk50,input wire rst,input wire [31:0] frame_id,input wire alarm,
    output reg [7:0] seg_sel,output reg [7:0] seg_data
);
    function integer bits_for;
        input integer n;integer v;
        begin v=n-1;bits_for=0;while(v>0)begin bits_for=bits_for+1;v=v>>1;end
              if(bits_for<1)bits_for=1;end
    endfunction
    localparam integer SCAN_DIV=CLK_HZ/(DIGIT_HZ*8);
    localparam integer BLINK_DIV=CLK_HZ/(BLINK_HZ*2);
    reg [bits_for(SCAN_DIV)-1:0] scan_count;
    reg [bits_for(BLINK_DIV)-1:0] blink_count;
    reg [2:0] digit;
    reg blink;
    reg [3:0] hex_value;
    function [7:0] hex_segments;
        input [3:0] h;
        begin case(h)
          0:hex_segments=8'hc0;1:hex_segments=8'hf9;
          2:hex_segments=8'ha4;3:hex_segments=8'hb0;
          4:hex_segments=8'h99;5:hex_segments=8'h92;
          6:hex_segments=8'h82;7:hex_segments=8'hf8;
          8:hex_segments=8'h80;9:hex_segments=8'h90;
          10:hex_segments=8'h88;11:hex_segments=8'h83;
          12:hex_segments=8'hc6;13:hex_segments=8'ha1;
          14:hex_segments=8'h86;default:hex_segments=8'h8e;
        endcase end
    endfunction
    always @(posedge clk50)begin
        if(rst)begin scan_count<=0;blink_count<=0;digit<=0;blink<=0;end
        else begin
            if(scan_count==SCAN_DIV-1)begin scan_count<=0;digit<=digit+1'b1;end
            else scan_count<=scan_count+1'b1;
            if(blink_count==BLINK_DIV-1)begin blink_count<=0;blink<=!blink;end
            else blink_count<=blink_count+1'b1;
        end
    end
    always @* begin
        case(digit)
          0:hex_value=frame_id[31:28];1:hex_value=frame_id[27:24];
          2:hex_value=frame_id[23:20];3:hex_value=frame_id[19:16];
          4:hex_value=frame_id[15:12];5:hex_value=frame_id[11:8];
          6:hex_value=frame_id[7:4];default:hex_value=frame_id[3:0];
        endcase
        // One blank system cycle between digits avoids ghosting.
        seg_sel=8'hff;seg_data=8'hff;
        if(!rst && scan_count!=0)begin
            seg_sel=~(8'b00000001<<digit);seg_data=hex_segments(hex_value);
            if(alarm && blink && digit==7)seg_data[7]=0;
        end
    end
endmodule
