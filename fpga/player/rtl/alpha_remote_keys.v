// Read-only player controls over the already connected UART. No SD-write path.
// Packet: 41 4b 01 seq cmd mask CRC32LE(version,seq,cmd,mask).
// cmd1 short key,2 long key,3 rescan,4 status,5 master volume0..100(default20).
// ACK is carried in ALPHAST2. Successful sequence repeats are idempotent.
module alpha_remote_keys #(parameter TIMEOUT_CYCLES=16777216,SERIAL_CRC=0)(
 input clk,rst,input[7:0]data,input valid,input busy,
 output reg[3:0]short_press,long_press,output reg scan,
 output reg[7:0]ack_seq,ack_cmd,ack_status,output reg[7:0]volume_percent,input local_volume_set,input[7:0]local_volume);
 reg[3:0]pos;reg[23:0]timer;reg[7:0]version,seq,cmd,mask;
 reg[31:0]crc,received;reg pending,have_applied;
 reg[7:0]crc_byte;reg[3:0]crc_bits;
 wire[31:0]serial_step=(crc>>1)^((crc[0]^crc_byte[0])?32'hedb88320:32'd0);
 reg[7:0]applied_seq,applied_cmd,applied_mask;
 wire one_key=mask==1||mask==2||mask==4||mask==8;
 function[31:0]step;input[31:0]c;input[7:0]b;reg[31:0]t;integer k;
 begin t=c^b;for(k=0;k<8;k=k+1)t=t[0] ? (t>>1)^32'hedb88320:t>>1;step=t;end endfunction
 always @(posedge clk)begin
  if(rst)begin pos<=0;timer<=0;version<=0;seq<=0;cmd<=0;mask<=0;crc<=32'hffffffff;received<=0;pending<=0;
   short_press<=0;long_press<=0;scan<=0;ack_seq<=0;ack_cmd<=0;ack_status<=0;
   volume_percent<=20;have_applied<=0;applied_seq<=0;applied_cmd<=0;applied_mask<=0;crc_byte<=0;crc_bits<=0;
  end else begin
   short_press<=0;long_press<=0;scan<=0;pending<=0;
   if(SERIAL_CRC&&crc_bits!=0)begin crc<=serial_step;crc_byte<=crc_byte>>1;crc_bits<=crc_bits-1'b1;end
   if(local_volume_set)volume_percent<=local_volume>100?8'd100:local_volume;
   if(pos!=0)begin
    if(timer==TIMEOUT_CYCLES-1)begin
     pos<=0;timer<=0;
     if(pos>=5)begin ack_seq<=seq;ack_cmd<=cmd;ack_status<=5;end
    end else timer<=timer+1'b1;
   end
   if(valid)begin
    timer<=0;
    if(SERIAL_CRC&&crc_bits!=0)begin pos<=0;crc_bits<=0;pending<=0;ack_seq<=seq;ack_cmd<=cmd;ack_status<=6;end
    else case(pos)
     0:if(data==8'h41)pos<=1;
     1:if(data==8'h4b)begin pos<=2;crc<=32'hffffffff;end else pos<=data==8'h41 ? 1:0;
     2:begin version<=data;if(SERIAL_CRC)begin crc_byte<=data;crc_bits<=8;end else crc<=step(crc,data);pos<=3;end
     3:begin seq<=data;if(SERIAL_CRC)begin crc_byte<=data;crc_bits<=8;end else crc<=step(crc,data);pos<=4;end
     4:begin cmd<=data;if(SERIAL_CRC)begin crc_byte<=data;crc_bits<=8;end else crc<=step(crc,data);pos<=5;end
     5:begin mask<=data;if(SERIAL_CRC)begin crc_byte<=data;crc_bits<=8;end else crc<=step(crc,data);pos<=6;end
     6,7,8:begin received[(pos-6)*8+:8]<=data;pos<=pos+1'b1;end
     9:begin received[31:24]<=data;pos<=0;pending<=1;end
     default:pos<=0;
    endcase
   end
   if(pending&&!(SERIAL_CRC&&valid&&crc_bits!=0))begin
    ack_seq<=seq;ack_cmd<=cmd;
    if(received!=~crc)ack_status<=1;
    else if(version!=1||!(((cmd==1||cmd==2)&&one_key)||((cmd==3||cmd==4)&&mask==0)||(cmd==5&&mask<=100)))ack_status<=2;
    else if(have_applied&&seq==applied_seq)ack_status<=(cmd==applied_cmd&&mask==applied_mask) ? 0:4;
    else if(busy&&cmd!=4&&cmd!=5)ack_status<=3;
    else begin
     ack_status<=0;have_applied<=1;applied_seq<=seq;applied_cmd<=cmd;applied_mask<=mask;
     if(cmd==1)short_press<=mask[3:0];if(cmd==2)long_press<=mask[3:0];if(cmd==3)scan<=1;if(cmd==5)volume_percent<=mask;
    end
   end
  end
 end
endmodule
