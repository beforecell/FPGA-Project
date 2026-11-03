// Alpha mechanical Verilog2001 port; upstream BSD-3-Clause retained.

module bfp_bitWidthDetector
  #(
    parameter FFT_BFPDW = 5,
    parameter FFT_DW = 16
    )
  (
   input wire [FFT_DW-1:0] operand0,
   input wire [FFT_DW-1:0] operand1,
   input wire [FFT_DW-1:0] operand2,
   input wire [FFT_DW-1:0] operand3,
   output wire [FFT_BFPDW-1:0] bw
   );

   reg [FFT_BFPDW-1:0]         bw_r;
   assign bw = bw_r;

   function [FFT_DW-1:0] ToAbsValue;
      input [FFT_DW-1:0]   operand;
      begin
         ToAbsValue = (operand[FFT_DW-1] == 1'b1) ?
                           (0 - operand[FFT_DW-1:0]) :
                           (operand[FFT_DW-1:0]);
      end
   endfunction
   
   wire [FFT_DW-1:0] operand_abs = 
               ToAbsValue( operand0 ) |
               ToAbsValue( operand1 ) |
               ToAbsValue( operand2 ) |
               ToAbsValue( operand3 );

   integer           i;
   always @* begin
      bw_r = 0;
      // Alpha portability: equivalent ascending priority loop, no break.
      for ( i = 0; i < FFT_DW; i=i+1 ) begin
         if ( operand_abs[i] ) begin
            bw_r = i + 1;
         end
      end
   end
   
endmodule // bfp_bitWidth


