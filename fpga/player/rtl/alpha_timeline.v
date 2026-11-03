// One sequential divider computes five positions in source-frame units.
// 576-pixel span,26 cycles/position;no divide in the pixel draw path.
module alpha_timeline #(parameter STATIC_INPUTS=0,ATOMIC_OUTPUT=1)(input clk,rst,update,input[15:0]frame,frame_count,
 input[63:0]keyframes,input[2:0]key_count,output wire[49:0]positions,output reg valid);
 localparam IDLE=0,LOAD=1,DIVIDE=2,COMMIT=3;
 reg[1:0]state;reg[2:0]which;reg[4:0]bit_index;reg[25:0]numer;
 reg[16:0]remain;reg[15:0]denom,current_q;reg[63:0]keys_q;reg[49:0]work;
 wire[15:0]current_value=STATIC_INPUTS?(frame_count>1?frame:0):current_q;
 wire[63:0]key_values=STATIC_INPUTS?keyframes:keys_q;
 reg[9:0]quotient;wire[15:0]value=which==0?current_value:key_values[(which-1'b1)*16+:16];
 wire[15:0]bounded=value<denom?value:denom;
 wire[25:0]scaled={1'b0,bounded,9'd0}+{4'd0,bounded,6'd0};
 wire[16:0]shifted={remain[15:0],numer[25]};
 wire[17:0]difference={1'b0,shifted}-{2'd0,denom};wire ge=!difference[17];
 wire[16:0]residue=ge?difference[16:0]:shifted;wire[9:0]next_q={quotient[8:0],ge};
 generate if(ATOMIC_OUTPUT)begin:atomic_result
  reg[49:0]published;assign positions=published;
  always @(posedge clk)if(rst)published<=0;else if(state==COMMIT)published<=work;
 end else begin:blanking_result
  // Used only before the bottom band is scanned. Consumers honor valid.
  assign positions=work;
 end endgenerate
 always @(posedge clk)begin
  if(rst)begin state<=IDLE;which<=0;bit_index<=0;numer<=0;remain<=0;denom<=1;current_q<=0;keys_q<=0;work<=0;quotient<=0;valid<=0;end
  else case(state)
   IDLE:if(update)begin if(!STATIC_INPUTS)begin current_q<=frame_count>1?frame:0;keys_q<=keyframes;end denom<=frame_count>1?frame_count-1'b1:16'd1;which<=0;state<=LOAD;if(!ATOMIC_OUTPUT)valid<=0;end
   LOAD:begin numer<=scaled;remain<=0;quotient<=0;bit_index<=0;state<=DIVIDE;end
   DIVIDE:begin
    numer<={numer[24:0],1'b0};remain<=residue;quotient<=next_q;
    if(bit_index==25)begin work[which*10+:10]<=10'd32+next_q;if(which==4)state<=COMMIT;else begin which<=which+1'b1;state<=LOAD;end end
    else bit_index<=bit_index+1'b1;
   end
   COMMIT:begin valid<=1;state<=IDLE;end
  endcase
 end
endmodule
