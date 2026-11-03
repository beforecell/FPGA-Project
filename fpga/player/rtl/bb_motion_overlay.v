// Combinational overlay; no pixel/timing latency. bbox belongs to the previous
// completed source frame and must be stable throughout the displayed frame.
module bb_motion_overlay (
    input wire [23:0] rgb,
    input wire [9:0] x, min_x, max_x,
    input wire [8:0] y, min_y, max_y,
    input wire pixel_valid, bbox_valid, alarm,
    output wire [23:0] out_rgb,
    output wire on_box, on_crosshair
);
    wire [10:0] sum_x={1'b0,min_x}+{1'b0,max_x};
    wire [9:0] sum_y={1'b0,min_y}+{1'b0,max_y};
    wire [9:0] center_x=sum_x[10:1];
    wire [8:0] center_y=sum_y[9:1];
    wire x_inside=x>=min_x && x<=max_x;
    wire y_inside=y>=min_y && y<=max_y;
    wire x_edge=x==min_x || x==max_x;
    wire y_edge=y==min_y || y==max_y;
    wire x_near=({1'b0,x}+11'd8>={1'b0,center_x}) &&
                ({1'b0,x}<={1'b0,center_x}+11'd8);
    wire y_near=({1'b0,y}+10'd8>={1'b0,center_y}) &&
                ({1'b0,y}<={1'b0,center_y}+10'd8);
    assign on_box=pixel_valid && bbox_valid &&
                  ((x_inside && y_edge)||(y_inside && x_edge));
    assign on_crosshair=pixel_valid && bbox_valid &&
                        ((x==center_x && y_near)||(y==center_y && x_near));
    assign out_rgb=on_box ? (alarm ? 24'hff2020 : 24'h20ff60) :
                   on_crosshair ? 24'hffff20 : rgb;
endmodule
