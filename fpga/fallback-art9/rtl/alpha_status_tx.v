module alpha_status_tx #(parameter CLK_HZ=100000000)(input clk,rst,input[7:0]flags,error,count,selected,
 input[15:0]frame_id,fps,input[31:0]media_ms,audio_samples,underflows,
 input[15:0]valid_mask,image_mask,input[7:0]selection_state,media_state,key_events,short_count,long_count,
 input[7:0]control_seq,control_cmd,control_status,input[31:0]asset_lba,asset_bytes,frame_commits,
 input[15:0]rate_q8_8,input[7:0]ui_state,list_state,input[31:0]elapsed_samples,output reg[7:0]data,output reg valid,input ready,input[223:0]analysis_debug);
 // Capture one aligned32-bit word/clock into a tiny synchronous RAM.
 // Each32-bit value (including the input/result frame pair) is atomic.
 // The20-word observation spans20 control clocks, not one atomic media frame.
 // This avoids576 payload flip-flops and preserves an 92-byte ALPHAST6 packet.
 reg[26:0]timer;reg active,capturing,fetch_wait;reg[4:0]capture_word;
 reg[6:0]index;reg[31:0]crc;
 wire[639:0]live_payload={analysis_debug,elapsed_samples,list_state,ui_state,rate_q8_8,frame_commits,asset_bytes,asset_lba,control_status,control_cmd,control_seq,long_count,short_count,key_events,media_state,selection_state,image_mask,valid_mask,underflows,audio_samples,media_ms,fps,frame_id,selected,count,error,flags};
 wire[31:0]payload_q;
 wire[6:0]payload_index=index-7'd8;
 bb3_sdp_ram #(.WIDTH(32),.AW(5),.DEPTH(32)) status_ram(clk,capturing,capture_word,live_payload[capture_word*32+:32],1'b1,payload_index[6:2],payload_q);
 function[31:0]step;input[31:0]c;input[7:0]b;reg[31:0]t;integer k;begin t=c^b;for(k=0;k<8;k=k+1)t=t[0] ? (t>>1)^32'hedb88320:t>>1;step=t;end endfunction
 function[7:0]magic;input[2:0]n;begin case(n)0:magic="A";1:magic="L";2:magic="P";3:magic="H";4:magic="A";5:magic="S";6:magic="T";7:magic="6";endcase end endfunction
 wire[7:0]next_byte=index<8 ? magic(index[2:0]):index<88 ? (payload_q>>{index[1:0],3'b000}):(~crc)>>{index[1:0],3'b000};
 always @(posedge clk)begin
  if(rst)begin timer<=0;active<=0;capturing<=0;capture_word<=0;fetch_wait<=0;index<=0;crc<=32'hffffffff;data<=0;valid<=0;end
  else if(!active)begin
   if(timer==CLK_HZ/2-1)begin timer<=0;active<=1;capturing<=1;capture_word<=0;index<=0;crc<=32'hffffffff;fetch_wait<=1;end
   else timer<=timer+1'b1;
  end else if(capturing)begin
   if(capture_word==19)capturing<=0;else capture_word<=capture_word+1'b1;
  end else if(fetch_wait)fetch_wait<=0;
  else if(!valid)begin data<=next_byte;valid<=1;end
  else if(ready)begin
   valid<=0;fetch_wait<=1;
   if(index<88)crc<=step(crc,data);
   if(index==91)begin active<=0;index<=0;end else index<=index+1'b1;
  end
 end
endmodule
