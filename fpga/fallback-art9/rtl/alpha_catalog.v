module alpha_catalog(input clk,rst,scan,input initialized,card_busy,card_done,card_valid,
 input[7:0]card_data,input[3:0]card_error,output reg start,output[31:0]lba,blocks,output ready,
 output reg loaded,busy,output reg[3:0]error,output reg[4:0]count,total_count,
 input[3:0]selected,output selected_ready,output[1:0]kind,
 output[31:0]asset_lba,asset_bytes,audio_lba,audio_samples,asset_crc,duration_ms,
 output[15:0]width,height,fps,frame_count,
 output reg[31:0]cue0_lba,cue1_lba,cue2_lba,cue3_lba,cue0_samples,cue1_samples,cue2_samples,cue3_samples,
 output reg[15:0]valid_mask,image_mask,
 input name_clk,input[3:0]name_item,input[4:0]name_char,output[7:0]name_data);
 reg[8:0]pos;reg[4:0]entry;reg[31:0]crc,expected;reg bad,seen,requested;
 reg cue_commit;reg[2:0]cue_number;reg[31:0]rlba,rbytes,ralba,rasamples;reg[1:0]rkind;
 reg[3:0]qindex,selected_latched;reg[6:0]qi;reg[1:0]qstate;reg[415:0]q;reg qdone,shift_query;
 wire we=busy&&card_valid&&entry!=0&&entry<=total_count&&pos<128;
 wire[10:0]wa={(entry[3:0]-4'd1),pos[6:0]};
 wire[10:0]qa={qindex,qi};wire[7:0]qd;
 alpha_index_ram names(clk,we,wa,card_data,qa,qd,name_clk,{name_item,7'd64}+name_char,name_data);
 assign lba=0;assign blocks=17;assign ready=1;
 assign selected_ready=loaded&&qdone&&qindex==selected&&qindex==selected_latched;
 assign kind=valid_mask[selected] ? q[8*8+:2]:2'd3;
 assign asset_lba=q[16*8+:32];assign asset_bytes=q[20*8+:32];
 assign width=q[24*8+:16];assign height=q[26*8+:16];assign fps=q[28*8+:16];
 assign frame_count=q[32*8+:16];assign duration_ms=q[36*8+:32];
 assign audio_lba=q[40*8+:32];assign audio_samples=q[44*8+:32];assign asset_crc=q[48*8+:32];
 function[31:0]crcbyte;input[31:0]c;input[7:0]b;reg[31:0]t;integer j;begin t=c^b;for(j=0;j<8;j=j+1)t=t[0] ? (t>>1)^32'hedb88320:t>>1;crcbyte=t;end endfunction
 function[7:0]magic;input header;input[2:0]n;begin
  if(header)case(n)0:magic="A";1:magic="L";2:magic="P";3:magic="H";4:magic="A";5:magic="1";6:magic="0";7:magic="0";endcase
  else case(n)0:magic="A";1:magic="1";2:magic="A";3:magic="S";4:magic="S";5:magic="E";6:magic="T";7:magic="1";endcase
 end endfunction
 always @(posedge clk)begin
  if(rst)begin loaded<=0;busy<=0;start<=0;error<=0;count<=0;total_count<=0;pos<=0;entry<=0;crc<=32'hffffffff;expected<=0;bad<=0;seen<=0;requested<=1;
   valid_mask<=0;image_mask<=0;qindex<=0;selected_latched<=0;qi<=0;qstate<=0;q<=0;qdone<=0;shift_query<=0;rlba<=0;rbytes<=0;ralba<=0;rasamples<=0;rkind<=0;
   cue_commit<=0;cue_number<=0;cue0_lba<=0;cue1_lba<=0;cue2_lba<=0;cue3_lba<=0;cue0_samples<=0;cue1_samples<=0;cue2_samples<=0;cue3_samples<=0;
  end else begin
   start<=0;cue_commit<=0;selected_latched<=selected;shift_query<=0;
   // A dedicated registered strobe drives the wide descriptor shift bank.
   // Its enable path no longer includes the chooser state and index compare.
   if(shift_query)q<={qd,q[415:8]};
   if(cue_commit)case(cue_number)
    1:begin cue0_lba<=ralba;cue0_samples<=rasamples;end
    2:begin cue1_lba<=ralba;cue1_samples<=rasamples;end
    3:begin cue2_lba<=ralba;cue2_samples<=rasamples;end
    4:begin cue3_lba<=ralba;cue3_samples<=rasamples;end
    default:;
   endcase
   if(!busy&&requested&&initialized&&!card_busy)begin start<=1;busy<=1;requested<=0;entry<=0;pos<=0;crc<=32'hffffffff;bad<=0;seen<=0;error<=0;valid_mask<=0;image_mask<=0;end
   if(scan&&!busy)begin loaded<=0;qdone<=0;qi<=0;qstate<=0;qindex<=selected;requested<=1;end
   if(busy)begin
    if(card_busy)seen<=1;
    if(card_valid)begin
     // Parse byte lanes without entry gating; only validated records are committed.
     // Unused/header scratch values are overwritten before any record commit.
     case(pos)
       16,17,18,19:rlba[(pos-16)*8+:8]<=card_data;
       20,21,22,23:rbytes[(pos-20)*8+:8]<=card_data;
       40,41,42,43:ralba[(pos-40)*8+:8]<=card_data;
       44,45,46,47:rasamples[(pos-44)*8+:8]<=card_data;
       default:;
     endcase
     if(pos<508)crc<=crcbyte(crc,card_data);else expected[(pos-508)*8+:8]<=card_data;
     if(pos<8&&entry<=total_count&&card_data!=magic(entry==0,pos[2:0]))bad<=1;
     if(entry==0)begin
      case(pos)8:if(card_data!=1)bad<=1;9:if(card_data!=0)bad<=1;
       10:begin total_count<=card_data[4:0];if(card_data==0||card_data>16)bad<=1;end
       11,13:if(card_data!=0)bad<=1;14:if(card_data!=0)bad<=1;15:if(card_data!=2)bad<=1;
       12:begin count<=card_data[4:0];if(card_data==0||card_data>12)bad<=1;end
       default:;
      endcase
     end else if(entry<=total_count)begin
      case(pos)
       8:begin rkind<=card_data[1:0];if(card_data>2)bad<=1;end
       12:if(card_data!=entry-1)bad<=1;

       default:;
      endcase
     end
     pos<=pos+1'b1;
     if(pos==511)begin
      pos<=0;entry<=entry+1'b1;crc<=32'hffffffff;expected<=0;bad<=0;
      if(entry==0)begin if(bad||count>total_count||{card_data,expected[23:0]}!=~crc)error<=1;end
      else if(entry<=total_count)begin
       valid_mask[entry-1]<=!bad&&{card_data,expected[23:0]}==~crc&&rlba>=4096&&rbytes!=0&&(entry>count ? rkind==2:rkind<2);
       image_mask[entry-1]<=rkind==1; // Type map; validity remains a separate mask.
       if(entry>count&&rkind==2&&!bad&&{card_data,expected[23:0]}==~crc)begin cue_commit<=1;cue_number<=entry-count;end
      end
     end
    end
    if(card_done&&seen)begin busy<=0;loaded<=error==0&&card_error==0;if(card_error!=0)error<=card_error;end
   end
   if(loaded&&!busy)begin
    if(qindex!=selected_latched||!qdone)begin
     if(qindex!=selected_latched)begin qindex<=selected_latched;qi<=0;qstate<=0;qdone<=0;end
     else case(qstate)
      0:qstate<=1;1:begin qstate<=2;shift_query<=1;end
      2:begin if(qi==51)begin qdone<=1;qstate<=0;end else begin qi<=qi+1'b1;qstate<=0;end end
     endcase
    end
   end
   // Invalidate before changing the address tag on the following cycle. A
   // consumer must never see ready rise on an old descriptor with a new tag.
   if(selected_latched!=selected)qdone<=0;
  end
 end
endmodule

// Two physical 9K pages; A is scan-write/query-read, B is pixel name lookup.
module alpha_index_ram(input ca,we,input[10:0]wa,input[7:0]din,input[10:0]ra,output[7:0]qa,
 input cb,input[10:0]rb,output[7:0]qb);
 `ifdef __ICARUS__
 reg[7:0]mem[0:2047];reg[7:0]a,b;
 always @(posedge ca)begin if(we)mem[wa]<=din;a<=mem[ra];end
 always @(posedge cb)b<=mem[rb];assign qa=a;assign qb=b;
 `else
 wire[15:0]aa,bb;reg ba,bbank;always @(posedge ca)ba<=ra[10];always @(posedge cb)bbank<=rb[10];
 genvar n;generate for(n=0;n<2;n=n+1)begin:page
 EG_LOGIC_BRAM #(.DATA_WIDTH_A(8),.DATA_WIDTH_B(8),.ADDR_WIDTH_A(10),.ADDR_WIDTH_B(10),.DATA_DEPTH_A(1024),.DATA_DEPTH_B(1024),.BYTE_ENABLE(0),.MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),.RESETMODE("SYNC"),.IMPLEMENT("9K")) ram(
 .clka(ca),.cea(1'b1),.wea(we&&wa[10]==n),.rsta(1'b0),.ocea(1'b1),.dia(din),.addra(we ? wa[9:0]:ra[9:0]),.bea(1'b1),.doa(aa[n*8+:8]),
 .clkb(cb),.ceb(1'b1),.web(1'b0),.rstb(1'b0),.oceb(1'b1),.dib(8'd0),.addrb(rb[9:0]),.beb(1'b1),.dob(bb[n*8+:8]));end endgenerate
 assign qa=ba ? aa[15:8]:aa[7:0];assign qb=bbank ? bb[15:8]:bb[7:0];
 `endif
endmodule
