module alpha_status_tx #(parameter CLK_HZ=100000000,KEYFRAME_PROTOCOL=0,SHARED_RAM=0)(input clk,rst,input[7:0]flags,error,count,selected,
 input[15:0]frame_id,fps,input[31:0]media_ms,audio_samples,underflows,
 input[15:0]valid_mask,image_mask,input[7:0]selection_state,media_state,key_events,short_count,long_count,
 input[7:0]control_seq,control_cmd,control_status,input[31:0]asset_lba,asset_bytes,frame_commits,
 input[15:0]rate_q8_8,input[7:0]ui_state,list_state,input[31:0]elapsed_samples,output reg[7:0]data,output reg valid,input ready,input[223:0]analysis_debug,input[127:0]key_debug,
 output ram_we,ram_re,output[4:0]ram_wa,ram_ra,output[31:0]ram_din,input[31:0]ram_q,input ram_wready,ram_rready);
 // Capture one aligned32-bit word/clock into a tiny synchronous RAM.
 // Each32-bit value (including the input/result frame pair) is atomic.
 // The20-word observation spans20 control clocks, not one atomic media frame.
 // This avoids576 payload flip-flops and preserves an 92-byte ALPHAST6 packet.
 reg[26:0]timer;reg active,capturing;reg[1:0]fetch_wait;reg[4:0]capture_word;
 reg[6:0]index;reg[31:0]crc;
 reg[7:0]crc_byte;reg[3:0]crc_bits;
 reg[7:0]key_generation_start;
 wire[31:0]key_tail={key_debug[127:104],key_generation_start};
 wire[639:0]live_payload={analysis_debug,(KEYFRAME_PROTOCOL?key_tail:elapsed_samples),list_state,ui_state,rate_q8_8,(KEYFRAME_PROTOCOL?key_debug[95:64]:frame_commits),(KEYFRAME_PROTOCOL?key_debug[63:32]:asset_bytes),(KEYFRAME_PROTOCOL?key_debug[31:0]:asset_lba),control_status,control_cmd,control_seq,long_count,short_count,key_events,media_state,selection_state,image_mask,valid_mask,underflows,audio_samples,media_ms,fps,frame_id,selected,count,error,flags};
 wire[31:0]payload_q;reg[31:0]word_q;
 wire[6:0]payload_index=index-7'd8;
 wire write_grant=SHARED_RAM?ram_wready:1'b1,read_grant=SHARED_RAM?ram_rready:1'b1;
 assign ram_we=capturing;assign ram_re=fetch_wait==1&&index>=8&&index<88&&crc_bits==0;
 assign ram_wa=capture_word;assign ram_ra=payload_index[6:2];assign ram_din=live_payload[capture_word*32+:32];
 generate if(SHARED_RAM)begin:shared_storage
  assign payload_q=ram_q;
 end else begin:private_storage
  bb3_sdp_ram #(.WIDTH(32),.AW(5),.DEPTH(32)) status_ram(clk,ram_we&&write_grant,ram_wa,ram_din,ram_re&&read_grant,ram_ra,payload_q);
 end endgenerate
 // UART has thousands of control clocks between bytes. Eight one-bit CRC
 // steps use the same polynomial/result without an8-level XOR network.
 // This affects telemetry only;streaming TF/frame CRC engines stay unchanged.
 wire[31:0]crc_step=(crc>>1)^((crc[0]^crc_byte[0])?32'hedb88320:32'd0);
 function[7:0]magic;input[2:0]n;begin case(n)0:magic="A";1:magic="L";2:magic="P";3:magic="H";4:magic="A";5:magic="S";6:magic="T";7:magic=KEYFRAME_PROTOCOL?"7":"6";endcase end endfunction
 wire[7:0]next_byte=index<8 ? magic(index[2:0]):index<88 ? (word_q>>{index[1:0],3'b000}):(~crc)>>{index[1:0],3'b000};
 always @(posedge clk)begin
  if(rst)begin timer<=0;active<=0;capturing<=0;capture_word<=0;fetch_wait<=0;index<=0;crc<=32'hffffffff;data<=0;valid<=0;key_generation_start<=0;word_q<=0;crc_byte<=0;crc_bits<=0;end
  else if(!active)begin
   if(timer==CLK_HZ/2-1)begin timer<=0;active<=1;capturing<=1;capture_word<=0;index<=0;crc<=32'hffffffff;fetch_wait<=1;key_generation_start<=key_debug[111:104];end
   else timer<=timer+1'b1;
  end else if(capturing&&write_grant)begin
   if(capture_word==19)capturing<=0;else capture_word<=capture_word+1'b1;
  end else if(capturing)begin end
  else if(crc_bits!=0)begin crc<=crc_step;crc_byte<=crc_byte>>1;crc_bits<=crc_bits-1'b1;end
  else if(fetch_wait==1)begin
   if(index<8||index>=88)fetch_wait<=0;
   else if(read_grant)fetch_wait<=2;
  end else if(fetch_wait==2)begin word_q<=payload_q;fetch_wait<=0;end
  else if(!valid)begin data<=next_byte;valid<=1;end
  else if(ready)begin
   valid<=0;fetch_wait<=1;
   if(index<88)begin crc_byte<=data;crc_bits<=8;end
   if(index==91)begin active<=0;index<=0;end else index<=index+1'b1;
  end
 end
endmodule
