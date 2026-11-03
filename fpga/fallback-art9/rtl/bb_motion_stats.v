// Streaming frame statistics. Coordinates belong to the source raster.
// Configuration is latched at sof. sof may coincide with the first valid pixel.
// energy = sum(delta for delta > threshold), no contribution without history.
// eof publishes the CURRENT complete frame, including a same-edge final pixel.
// If eof is tied low, the next sof still publishes the previous frame. A frame
// finalized by eof is not published again, and further pixels are ignored until
// the next sof. A floating/Z eof in simulation does not request finalization.
// anomaly is a one-clock pulse at the FIRST accepted pixel crossing the latched
// threshold (inclusive). It identifies the frame currently being accumulated.
module bb_motion_stats (
    input wire clk, rst, sof, eof, pixel_valid, history_valid,
    input wire [9:0] x,
    input wire [8:0] y,
    input wire [7:0] delta, threshold,
    input wire [31:0] frame_id, anomaly_threshold,
    output reg summary_valid, bbox_valid,
    output reg [9:0] min_x, max_x,
    output reg [8:0] min_y, max_y,
    output reg [31:0] energy, summary_frame_id,
    output reg [18:0] motion_count,
    output reg anomaly,
    output reg [31:0] anomaly_frame_id
);
    reg started, completed, alarmed;
    reg [7:0] frame_threshold;
    reg [31:0] frame_alarm_threshold, current_frame_id, sum;
    reg [18:0] count;
    reg [9:0] lo_x, hi_x;
    reg [8:0] lo_y, hi_y;
    wire [7:0] effective_threshold = sof ? threshold : frame_threshold;
    wire [31:0] effective_alarm = sof ? anomaly_threshold : frame_alarm_threshold;
    wire [31:0] base_sum = sof ? 32'd0 : sum;
    wire accepted = pixel_valid && history_valid && (started || sof) && (!completed || sof);
    wire moving = accepted && delta > effective_threshold;
    wire [31:0] next_sum = base_sum + (moving ? {24'd0,delta} : 32'd0);
    wire [18:0] next_count = (sof ? 19'd0 : count)+(moving ? 19'd1 : 19'd0);
    wire [9:0] next_lo_x=moving && (sof || count==0 || x<lo_x) ? x : (sof ? 10'h3ff : lo_x);
    wire [9:0] next_hi_x=moving && (sof || count==0 || x>hi_x) ? x : (sof ? 10'd0 : hi_x);
    wire [8:0] next_lo_y=moving && (sof || count==0 || y<lo_y) ? y : (sof ? 9'h1ff : lo_y);
    wire [8:0] next_hi_y=moving && (sof || count==0 || y>hi_y) ? y : (sof ? 9'd0 : hi_y);
    wire first_alarm = moving && !(alarmed && !sof) && effective_alarm != 0 &&
                            base_sum < effective_alarm && next_sum >= effective_alarm;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            started<=0; completed<=0; alarmed<=0; frame_threshold<=0; frame_alarm_threshold<=0;
            current_frame_id<=0; sum<=0; count<=0; lo_x<=10'h3ff; hi_x<=0;
            lo_y<=9'h1ff; hi_y<=0; summary_valid<=0; bbox_valid<=0;
            min_x<=10'h3ff; max_x<=0; min_y<=9'h1ff; max_y<=0;
            energy<=0; motion_count<=0; summary_frame_id<=0;
            anomaly<=0; anomaly_frame_id<=0;
        end else begin
            summary_valid<=0; anomaly<=0;
            if (sof) begin
                if(started && !completed) begin
                    summary_valid<=1;
                    bbox_valid<=count!=0;
                    min_x<=lo_x; max_x<=hi_x; min_y<=lo_y; max_y<=hi_y;
                    energy<=sum; motion_count<=count; summary_frame_id<=current_frame_id;
                end
                started<=1; completed<=0; alarmed<=0;
                frame_threshold<=threshold; frame_alarm_threshold<=anomaly_threshold;
                current_frame_id<=frame_id;
                sum<=0; count<=0; lo_x<=10'h3ff; hi_x<=0; lo_y<=9'h1ff; hi_y<=0;
            end
            if (moving) begin
                sum<=next_sum;
                count<=next_count;
                lo_x<=next_lo_x;hi_x<=next_hi_x;lo_y<=next_lo_y;hi_y<=next_hi_y;
            end
            if (first_alarm) begin
                alarmed<=1; anomaly<=1;
                anomaly_frame_id<=sof ? frame_id : current_frame_id;
            end
            // eof and sof together denote a new single-cycle frame. Its final
            // summary wins over a possible sof-only previous-frame fallback.
            if (eof && (started || sof) && (!completed || sof)) begin
                completed<=1;summary_valid<=1;
                summary_frame_id<=sof ? frame_id : current_frame_id;
                energy<=next_sum;motion_count<=next_count;bbox_valid<=next_count!=0;
                min_x<=next_lo_x;max_x<=next_hi_x;min_y<=next_lo_y;max_y<=next_hi_y;
            end
        end
    end
endmodule
