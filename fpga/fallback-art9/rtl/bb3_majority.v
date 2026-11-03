// A3x3majority filter with explicit zero borders. The input is a complete
//320x240 raster; output is complete as well, finishing a zero last row after
//input EOF. A synchronous 320x2 RAM replaces 640 enabled shift registers.
//Read x first, then write that column on the following cycle. The complete
//sample (including coordinates) is delayed with the RAM read. Rows 0/1 prime
//the memory; zero borders make power-up RAM contents unobservable.
module bb3_majority(input clk,rst,input sample_valid,input[8:0]x,input[7:0]y,
 input bit_in,input camera_mode,
 output reg valid,output reg[8:0]ox,output reg[7:0]oy,output reg bit_out,output reg eof);
 reg[1:0]rows[0:319];reg[1:0]row_q;reg[1:0]h0,h1,h2;
 reg v1,bit1,cam1;reg[8:0]x1;reg[7:0]y1;
 reg end_column,flush_row;reg[7:0]end_y;reg[8:0]flush_x;
 wire a=row_q[0],b=row_q[1];
 wire[3:0]count={3'd0,bit1}+{3'd0,a}+{3'd0,b}+
  {3'd0,h0[0]}+{3'd0,h0[1]}+{3'd0,h1[0]}+{3'd0,h1[1]}+{3'd0,h2[0]}+{3'd0,h2[1]};
 always @(posedge clk)begin
  if(sample_valid)row_q<=rows[x];
  if(v1&&!rst)rows[x1]<={a,bit1};
  if(rst)begin v1<=0;bit1<=0;cam1<=0;x1<=0;y1<=0;end
  else begin v1<=sample_valid;if(sample_valid)begin bit1<=bit_in;cam1<=camera_mode;x1<=x;y1<=y;end end
 end
 always @(posedge clk)begin
  if(rst)begin h0<=0;h1<=0;h2<=0;end_column<=0;flush_row<=0;end_y<=0;flush_x<=0;valid<=0;ox<=0;oy<=0;bit_out<=0;eof<=0;end
  else begin
   valid<=0;eof<=0;end_column<=0;
   if(v1)begin
    if(x1==0)begin h0<={1'b0,bit1};h1<={1'b0,a};h2<={1'b0,b};end
    else begin h0<={h0[0],bit1};h1<={h1[0],a};h2<={h2[0],b};end
    if(x1>=1&&y1>=1)begin valid<=1;ox<=x1-1'b1;oy<=y1-1'b1;bit_out<=x1>=2&&y1>=2&&(count>=(cam1?6:5));end
    if(x1==319&&y1>=1)begin end_column<=1;end_y<=y1-1'b1;end
   end
   if(end_column)begin valid<=1;ox<=319;oy<=end_y;bit_out<=0;
    if(end_y==238)begin flush_row<=1;flush_x<=0;end
   end
   if(flush_row)begin valid<=1;ox<=flush_x;oy<=239;bit_out<=0;
    if(flush_x==319)begin flush_row<=0;eof<=1;end else flush_x<=flush_x+1'b1;
   end
  end
 end
endmodule
