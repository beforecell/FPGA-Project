// A layout-independent320x240 analysis stream. Quad input already contains
// area averages from the block decoder; full input is reduced here using2
// 320x27bit row-pair stores. Matching same2x2integer filter in either mode.
module bb3_reduce2(input clk,rst,input enable,quad_mode,de,
 input[9:0]x,input[8:0]y,input[23:0]rgb,previous,
 output reg valid,output reg[8:0]ox,output reg[7:0]oy,
 output reg[23:0]current_rgb,previous_rgb);
 reg[23:0]even_c,even_p;reg[26:0]odd_c,odd_p;
 wire[26:0]pair_c={{1'b0,even_c[23:16]}+{1'b0,rgb[23:16]},
                  {1'b0,even_c[15:8]}+{1'b0,rgb[15:8]},
                  {1'b0,even_c[7:0]}+{1'b0,rgb[7:0]}};
 wire[26:0]pair_p={{1'b0,even_p[23:16]}+{1'b0,previous[23:16]},
                  {1'b0,even_p[15:8]}+{1'b0,previous[15:8]},
                  {1'b0,even_p[7:0]}+{1'b0,previous[7:0]}};
 wire full_sample=enable&&de&&!quad_mode;
 wire save_pair=full_sample&&x[0]&&!y[0];
 wire read_pair=full_sample&&x[0]&&y[0];
 wire[26:0]above_c,above_p;
 bb3_sdp_ram #(.WIDTH(27),.AW(9),.DEPTH(512)) line_c(clk,save_pair,x[9:1],pair_c,read_pair,x[9:1],above_c);
 bb3_sdp_ram #(.WIDTH(27),.AW(9),.DEPTH(512)) line_p(clk,save_pair,x[9:1],pair_p,read_pair,x[9:1],above_p);
 reg pending;reg[8:0]px;reg[7:0]py;
 function[23:0]avg;input[26:0]a,b;reg[9:0]r,g,c;begin
  r={1'b0,a[26:18]}+{1'b0,b[26:18]}+2;
  g={1'b0,a[17:9]}+{1'b0,b[17:9]}+2;
  c={1'b0,a[8:0]}+{1'b0,b[8:0]}+2;avg={r[9:2],g[9:2],c[9:2]};end endfunction
 always @(posedge clk)begin
  if(rst)begin even_c<=0;even_p<=0;odd_c<=0;odd_p<=0;pending<=0;px<=0;py<=0;valid<=0;ox<=0;oy<=0;current_rgb<=0;previous_rgb<=0;end
  else begin
   pending<=read_pair;valid<=0;
   if(full_sample&&!x[0])begin even_c<=rgb;even_p<=previous;end
   if(read_pair)begin odd_c<=pair_c;odd_p<=pair_p;px<=x[9:1];py<=y[8:1];end
   if(pending)begin valid<=1;ox<=px;oy<=py;current_rgb<=avg(above_c,odd_c);previous_rgb<=avg(above_p,odd_p);end
   if(enable&&de&&quad_mode&&x<320&&y<240)begin valid<=1;ox<=x[8:0];oy<=y[7:0];current_rgb<=rgb;previous_rgb<=previous;end
  end
 end
endmodule
