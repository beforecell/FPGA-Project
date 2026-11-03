// PCM source for the official HDMI transmitter's video-clock sample interface.
// Fractional sample enable gives exactly SAMPLE_HZ samples per CLK_HZ clocks.
// alarm/severity must already be synchronous to clk. Alarm switches frequency
// at the next sample (<=20.84us at 48kHz); no claim of acoustic 1-clock latency.
// Square-wave DDS: background 375Hz, alarm 1125 + severity*187.5Hz at 48kHz.
// stereo 24-bit two's-complement. alarm_event frame ID is handled upstream.
module bb_alarm_pcm #(
    parameter integer CLK_HZ=25000000,
    parameter integer SAMPLE_HZ=48000,
    parameter signed [23:0] AMPLITUDE=24'sd700000
) (
    input wire clk, rst, alarm, enable,
    input wire [3:0] severity,
    output reg sample_valid,
    output reg [23:0] pcm_left, pcm_right
);
    reg [31:0] sample_acc;
    reg [7:0] phase;
    wire [32:0] sample_sum={1'b0,sample_acc}+SAMPLE_HZ;
    wire [7:0] phase_step=alarm ? 8'd6+{4'd0,severity} : 8'd2;
    wire signed [23:0] value=!enable ? 24'sd0 : (phase[7] ? AMPLITUDE : -AMPLITUDE);
    always @(posedge clk or posedge rst) begin
        if (rst) begin sample_acc<=0; phase<=0; sample_valid<=0; pcm_left<=0; pcm_right<=0; end
        else begin
            sample_valid<=0;
            if (sample_sum>=CLK_HZ) begin
                sample_acc<=sample_sum-CLK_HZ;
                phase<=phase+phase_step;
                sample_valid<=1; pcm_left<=value; pcm_right<=value;
            end else sample_acc<=sample_sum[31:0];
        end
    end
endmodule
