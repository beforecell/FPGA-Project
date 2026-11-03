// BSD-3-Clause R2FFT core; Alpha wrapper uses 256 samples, rectangular window.
// Actual PCM only. Processing may skip acquisition while the FFT is busy;
// it NEVER stalls or alters the HDMI audio stream.
module alpha_spectrum(input clk,rst,enable,frame_start,input sample_valid,input signed[15:0]sample,
 output[7:0]bar_value,input[7:0]bar_query,output reg[7:0]peak_bin,output reg[15:0]peak_level,
 output reg updated,output reg[31:0]skipped_samples);
 wire done;wire[2:0]status;wire signed[7:0]exponent;
 reg fin,dma;reg[7:0]addr;wire signed[15:0]re,im;
 wire twen;wire[5:0]twa;reg[15:0]tw;
 wire r0,r1,w0,w1;wire[6:0]ra0,ra1,wa0,wa1;wire[31:0]q0,q1,d0,d1;
 R2FFT #(.FFT_LENGTH(256),.FFT_DW(16),.PL_DEPTH(3)) fft(
  .clk(clk),.rst(rst||!enable),.autorun(1'b1),.run(1'b0),.fin(fin),.ifft(1'b0),
  .done(done),.status(status),.bfpexp(exponent),.sact_istream(sample_valid&&enable&&status==1),
  .sdw_istream_real(sample),.sdw_istream_imag(16'sd0),.dmaact(dma),.dmaa(addr),.dmadr_real(re),.dmadr_imag(im),
  .twact(twen),.twa(twa),.twdr_cos(tw),.ract_ram0(r0),.ra_ram0(ra0),.rdr_ram0(q0),.wact_ram0(w0),.wa_ram0(wa0),.wdw_ram0(d0),
  .ract_ram1(r1),.ra_ram1(ra1),.rdr_ram1(q1),.wact_ram1(w1),.wa_ram1(wa1),.wdw_ram1(d1));
 bb3_sdp_ram #(.WIDTH(32),.AW(7),.DEPTH(128)) ram0(clk,w0,wa0,d0,r0,ra0,q0);
 bb3_sdp_ram #(.WIDTH(32),.AW(7),.DEPTH(128)) ram1(clk,w1,wa1,d1,r1,ra1,q1);
 `include "alpha_twiddle.vh"
 always @(posedge clk)if(twen)tw<=alpha_cos(twa);

 // 129 single-sided bins:0..128. DC is explicitly removed. Interior bins
 // are doubled before per-transform peak normalization. Magnitude is |Re|+|Im|.
 reg[3:0]state;reg[17:0]maxmag;reg[7:0]maxbin;
 reg raw_we;reg[7:0]raw_wa,norm_addr;reg[17:0]raw_d;wire[17:0]raw_q;
 bb3_sdp_ram #(.WIDTH(18),.AW(8),.DEPTH(256)) raw_ram(clk,raw_we,raw_wa,raw_d,1'b1,norm_addr,raw_q);
 reg display_bank,display_valid,bar_we;reg[8:0]bar_wa;reg[7:0]bar_wdata;wire[7:0]bar_q;
 bb3_sdp_ram #(.WIDTH(8),.AW(9),.DEPTH(512)) points(clk,bar_we,bar_wa,bar_wdata,1'b1,{display_bank,bar_query},bar_q);
 assign bar_value=display_valid ? bar_q:8'd0;
 wire[15:0]ar=re[15] ? -re:re,ai=im[15] ? -im:im;
 wire[16:0]l1={1'b0,ar}+{1'b0,ai};
 wire[17:0]mag=addr==0 ? 18'd0:addr==128 ? {1'b0,l1}:{l1,1'b0};
 reg[17:0]remainder;reg[7:0]quotient;reg[3:0]bitn;
 wire[18:0]shift_rem={remainder,1'b0};
 wire ge=shift_rem>={1'b0,maxmag};
 wire[7:0]next_quot={quotient[6:0],ge};
 always @(posedge clk)begin
  if(rst||!enable)begin
   peak_bin<=0;peak_level<=0;updated<=0;skipped_samples<=0;state<=0;fin<=0;dma<=0;addr<=0;maxmag<=0;maxbin<=0;
   display_bank<=0;display_valid<=0;bar_we<=0;bar_wa<=0;bar_wdata<=0;
   raw_we<=0;raw_wa<=0;raw_d<=0;norm_addr<=0;remainder<=0;quotient<=0;bitn<=0;
  end else begin
   updated<=0;fin<=0;bar_we<=0;raw_we<=0;
   if(sample_valid&&status!=1)skipped_samples<=skipped_samples+1'b1;
   case(state)
    0:if(done)begin addr<=0;dma<=1;maxmag<=0;maxbin<=0;state<=1;end
    1:state<=2;
    2:state<=3;
    3:begin
     raw_we<=1;raw_wa<=addr;raw_d<=mag;
     if(mag>maxmag)begin maxmag<=mag;maxbin<=addr;end
     if(addr==128)begin dma<=0;norm_addr<=0;state<=4;end
     else begin addr<=addr+1'b1;state<=1;end
    end
    4:state<=5;
    5:begin
     if(maxmag==0||raw_q==0)begin bar_wdata<=0;state<=7;end
     else if(raw_q>=maxmag)begin bar_wdata<=255;state<=7;end
     else begin remainder<=raw_q;quotient<=0;bitn<=0;state<=6;end
    end
    6:begin
     remainder<=ge ? shift_rem-{1'b0,maxmag}:shift_rem;
     quotient<=next_quot;bitn<=bitn+1'b1;
     if(bitn==7)begin bar_wdata<=next_quot;state<=7;end
    end
    7:begin
     bar_we<=1;bar_wa<={!display_bank,norm_addr};
     if(norm_addr==128)state<=8;
     else begin norm_addr<=norm_addr+1'b1;state<=4;end
    end
    8:state<=9;
    9:if(frame_start)begin
     display_bank<=!display_bank;display_valid<=1;peak_bin<=maxbin;
     peak_level<=|maxmag[17:16] ? 16'hffff:maxmag[15:0];
     updated<=1;fin<=1;state<=10;
    end
    10:if(!done)state<=0;
    default:state<=0;
   endcase
  end
 end
endmodule
