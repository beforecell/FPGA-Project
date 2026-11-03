// Original read-only native SD 4-bit host, 50 MHz control clock in Alpha.
// 3.3 V Default Speed only: 200 kHz initialization, 25 MHz transfers (half_last=0).
// Bytes may have been delivered before a block CRC failure is reported.
// A consumer must discard its in-progress object/frame on any nonzero error.
module sd_native4 #(
    parameter integer INIT_CLOCKS = 400,
    parameter integer RESPONSE_TIMEOUT = 1024,
    parameter integer DATA_TIMEOUT = 4194303,
    parameter integer INIT_RETRIES = 4095
)(
    input wire clk, input wire rst,
    input wire start, input wire [31:0] lba, input wire [31:0] blocks,
    output reg initialized, output reg busy, output reg done,
    output reg [3:0] error, output reg [7:0] data, output reg valid,
    input wire ready,
    output wire [31:0] debug_status,output wire [31:0] debug_data,
    output reg sd_clk, inout wire sd_cmd, inout wire [3:0] sd_dat
);
    reg fast_clock;
    reg [7:0] divider;
    // Short metadata reads use12.5MHz;bulk frame reads retain25MHz.
    wire [7:0] half_last = fast_clock ? (read_blocks==1 ? 8'd1:8'd0) : 8'd124;
    wire pause_clock = valid && !ready && !sd_clk;
    wire rise_tick = !pause_clock && divider == half_last && !sd_clk;
    wire fall_tick = divider == half_last && sd_clk;
    reg read_sample_d1;
    // Receive20ns after the generated rising edge at25MHz. The round-trip
    // clock-pad/card/data-pad delay is absent from a zero-delay card model.
    // Command transmission and the eight-clock turnaround use real edges.
    wire sample_tick=fast_clock?read_sample_d1:rise_tick;
    always @(posedge clk)if(rst)read_sample_d1<=0;else read_sample_d1<=rise_tick;
    reg cmd_oe, cmd_out;
    assign sd_cmd = cmd_oe ? cmd_out : 1'bz;
    // Read-only host never drives DAT. Board resistors provide pull-ups.
    assign sd_dat = 4'bzzzz;
    wire cmd_in = sd_cmd;

    always @(posedge clk) begin
        if (rst) begin sd_clk <= 0; divider <= 0; end
        else if (pause_clock) divider <= 0;
        else if (divider == half_last) begin divider <= 0; sd_clk <= !sd_clk; end
        else divider <= divider + 1'b1;
    end

    function [6:0] crc7_bit;
        input [6:0] c; input b;
        begin crc7_bit = {c[5:0],1'b0} ^ ((c[6]^b) ? 7'h09 : 7'h00); end
    endfunction
    function [6:0] crc7_40;
        input [39:0] v; integer k; reg [6:0] c;
        begin c=0; for(k=39;k>=0;k=k-1) c=crc7_bit(c,v[k]); crc7_40=c; end
    endfunction
    function [15:0] crc16_bit;
        input [15:0] c; input b;
        begin crc16_bit={c[14:0],1'b0} ^ ((c[15]^b) ? 16'h1021 : 16'h0000); end
    endfunction

    localparam R_NONE=0,R_R1=1,R_R2=2,R_R3=3,R_R1B=4,R_R6=5,R_R7=6;
    reg cmd_go;
    reg [5:0] command;
    reg [31:0] argument;
    reg [2:0] response_kind;
    reg cmd_done;
    reg [3:0] cmd_error;
    reg [135:0] response;
    reg [47:0] command_frame;
    reg [5:0] transmit_bit;
    reg [7:0] response_count;
    reg [7:0] response_length;
    reg [6:0] response_crc;
    reg [22:0] command_wait;
    reg [2:0] busy_guard;
    reg [3:0] command_state;
    reg [3:0] command_idle_clocks;
    localparam C_IDLE=0,C_ALIGN=1,C_SEND=2,C_WAIT=3,C_RX=4,C_CHECK=5,C_BUSY=6;
    wire [31:0] response_payload = response[39:8];
    wire response_crc_good = response_crc == response[7:1];
    wire [31:0] r1_error_mask = 32'hfdffe008;

    always @(posedge clk) begin
        if (rst) begin
            cmd_oe<=0; cmd_out<=1; command_state<=C_IDLE;command_idle_clocks<=8;
            cmd_done<=0; cmd_error<=0; response<=0;
            command_frame<=0; transmit_bit<=0; response_count<=0;
            response_length<=0; response_crc<=0; command_wait<=0; busy_guard<=0;
        end else begin
            cmd_done<=0;
            // Required NRC/NCC turnaround: at least8 complete SD clocks in
            // Hi-Z after a response before driving the next command. A queued
            // command can wait in C_ALIGN; payload streaming is unchanged.
            if(rise_tick)begin
                if(command_state==C_IDLE || command_state==C_ALIGN)begin
                    if(command_idle_clocks<8)command_idle_clocks<=command_idle_clocks+1'b1;
                end else command_idle_clocks<=0;
            end
            case(command_state)
              C_IDLE: if(cmd_go) begin
                  command_frame <= {2'b01,command,argument,
                                    crc7_40({2'b01,command,argument}),1'b1};
                  transmit_bit<=47; cmd_error<=0; response<=0;
                  response_length <= response_kind==R_R2 ? 136 : 48;
                  command_state<=C_ALIGN;
              end
              C_ALIGN: if(fall_tick && command_idle_clocks==8) begin
                  cmd_oe<=1; cmd_out<=0; command_state<=C_SEND;
              end
              C_SEND: if(fall_tick) begin
                  if(transmit_bit==0) begin
                      cmd_oe<=0; cmd_out<=1; command_wait<=0;
                      if(response_kind==R_NONE) begin
                          cmd_done<=1; command_state<=C_IDLE;
                      end else command_state<=C_WAIT;
                  end else begin
                      transmit_bit<=transmit_bit-1'b1;
                      cmd_out<=command_frame[transmit_bit-1'b1];
                  end
              end
              C_WAIT: if(sample_tick) begin
                  if(!cmd_in) begin
                      response<=0; response_crc<=0; response_count<=1; command_state<=C_RX;
                  end else if(command_wait>=RESPONSE_TIMEOUT) begin
                      cmd_error<=1; cmd_done<=1; command_state<=C_IDLE;
                  end else command_wait<=command_wait+1'b1;
              end
              C_RX: if(sample_tick) begin
                  response<={response[134:0],cmd_in};
                  // The first start bit is zero, so its initial CRC is zero.
                  // Short responses cover positions 0..39; R2 covers 8..127.
                  if((response_kind!=R_R2 && response_count<40) ||
                     (response_kind==R_R2 && response_count>=8 && response_count<128))
                      response_crc<=crc7_bit(response_crc,cmd_in);
                  response_count<=response_count+1'b1;
                  if(response_count==response_length-1'b1) command_state<=C_CHECK;
              end
              C_CHECK: begin
                  // R2's CRC covers CID/CSD bits 127..8, excludes its 8-bit header.
                  // OCR response R3 has reserved all-ones CRC and no CRC protection.
                  if(!response[0] ||
                     (response_kind==R_R2 &&
                       (response[135:128]!=8'h3f || !response_crc_good)) ||
                     (response_kind!=R_R2 && response_kind!=R_R3 &&
                       (response[47:46]!=2'b00 || response[45:40]!=command || !response_crc_good)) ||
                     (response_kind==R_R3 && response[47:40]!=8'h3f)) begin
                      cmd_error<=2; cmd_done<=1; command_state<=C_IDLE;
                  end else if(((response_kind==R_R1 || response_kind==R_R1B) &&
                               ((response_payload&r1_error_mask)!=0)) ||
                              (response_kind==R_R6 && response_payload[15:13]!=0)) begin
                      cmd_error<=3; cmd_done<=1; command_state<=C_IDLE;
                  end else if(response_kind==R_R1B) begin
                      busy_guard<=0; command_wait<=0; command_state<=C_BUSY;
                  end else begin cmd_done<=1; command_state<=C_IDLE; end
              end
              C_BUSY: if(sample_tick) begin
                  if(busy_guard<4) busy_guard<=busy_guard+1'b1;
                  else if(sd_dat[0]) begin cmd_done<=1; command_state<=C_IDLE; end
                  if(command_wait>=DATA_TIMEOUT) begin
                      cmd_error<=1; cmd_done<=1; command_state<=C_IDLE;
                  end else command_wait<=command_wait+1'b1;
              end
              default: command_state<=C_IDLE;
            endcase
        end
    end

    reg data_go, data_abort;
    reg [31:0] read_blocks;
    reg data_done;
    reg [3:0] data_error;
    reg [2:0] data_state;
    reg [9:0] nibble_count;
    reg [3:0] high_nibble;
    reg [31:0] blocks_left;
    reg [15:0] crc0,crc1,crc2,crc3;
    reg [3:0] crc_bit_index;
    reg block_crc_bad;
    reg [22:0] data_wait;
    localparam D_IDLE=0,D_TOKEN=1,D_PAYLOAD=2,D_CRC=3,D_END=4;
    always @(posedge clk) begin
        if(rst) begin
            data<=0; valid<=0; data_done<=0; data_error<=0; data_state<=D_IDLE;
            nibble_count<=0; high_nibble<=0; blocks_left<=0;
            crc0<=0;crc1<=0;crc2<=0;crc3<=0;crc_bit_index<=0;
            block_crc_bad<=0;data_wait<=0;
        end else begin
            data_done<=0;
            if(valid && ready) valid<=0;
            if(data_abort) begin data_state<=D_IDLE; valid<=0; end
            else if(data_go) begin
                data_state<=D_TOKEN; blocks_left<=read_blocks;
                data_error<=0; data_wait<=0; valid<=0;
            end else if(sample_tick) begin
                case(data_state)
                  D_TOKEN: begin
                      if(sd_dat==4'h0) begin
                          nibble_count<=0;crc0<=0;crc1<=0;crc2<=0;crc3<=0;
                          block_crc_bad<=0; data_state<=D_PAYLOAD;
                      end else if(data_wait>=DATA_TIMEOUT) begin
                          data_error<=4;data_state<=D_IDLE;
                      end else data_wait<=data_wait+1'b1;
                  end
                  D_PAYLOAD: begin
                      crc0<=crc16_bit(crc0,sd_dat[0]);
                      crc1<=crc16_bit(crc1,sd_dat[1]);
                      crc2<=crc16_bit(crc2,sd_dat[2]);
                      crc3<=crc16_bit(crc3,sd_dat[3]);
                      if(!nibble_count[0]) high_nibble<=sd_dat;
                      else begin data<={high_nibble,sd_dat};valid<=1;end
                      if(nibble_count==1023) begin
                          data_state<=D_CRC;crc_bit_index<=15;
                      end else nibble_count<=nibble_count+1'b1;
                  end
                  D_CRC: begin
                      if(sd_dat!={crc3[crc_bit_index],crc2[crc_bit_index],
                                  crc1[crc_bit_index],crc0[crc_bit_index]}) block_crc_bad<=1;
                      if(crc_bit_index==0) data_state<=D_END;
                      else crc_bit_index<=crc_bit_index-1'b1;
                  end
                  D_END: begin
                      if(block_crc_bad || sd_dat!=4'hf) begin
                          data_error<=5;data_state<=D_IDLE;
                      end else if(blocks_left==1) begin
                          data_done<=1;data_state<=D_IDLE;
                      end else begin
                          blocks_left<=blocks_left-1'b1;data_wait<=0;data_state<=D_TOKEN;
                      end
                  end
                  default: begin end
                endcase
            end
        end
    end

    reg [5:0] state;
    reg [15:0] power_clocks;
    reg [3:0] gap_clocks;
    reg [11:0] init_attempt;
    reg [15:0] rca;
    reg high_capacity,legacy_card,stop_for_error;
    reg [31:0] read_lba;
    localparam M_POWER=0,M_CMD0=1,M_W0=2,M_GAP=3,M_CMD8=4,M_W8=5,
      M_CMD55=6,M_W55=7,M_ACMD41=8,M_W41=9,M_CMD2=10,M_W2=11,
      M_CMD3=12,M_W3=13,M_CMD7=14,M_W7=15,M_BUS55=16,M_WBUS55=17,
      M_BUS6=18,M_WBUS6=19,M_CMD16=20,M_W16=21,M_READY=22,
      M_READ=23,M_WREAD=24,M_READING=25,M_STOP=26,M_WSTOP=27,M_FAIL=28;

    task launch;
        input [5:0] c;input [31:0] a;input [2:0] r;input [5:0] n;
        begin command<=c;argument<=a;response_kind<=r;cmd_go<=1;state<=n;end
    endtask
    always @(posedge clk) begin
        if(rst) begin
            initialized<=0;busy<=1;done<=0;error<=0;fast_clock<=0;
            cmd_go<=0;command<=0;argument<=0;response_kind<=0;
            data_go<=0;data_abort<=0;read_blocks<=0;read_lba<=0;
            state<=M_POWER;power_clocks<=0;gap_clocks<=0;init_attempt<=0;
            rca<=0;high_capacity<=0;legacy_card<=0;stop_for_error<=0;
        end else begin
            done<=0;cmd_go<=0;data_go<=0;data_abort<=0;
            case(state)
              M_POWER: if(rise_tick) begin
                  if(power_clocks==INIT_CLOCKS-1) state<=M_CMD0;
                  else power_clocks<=power_clocks+1'b1;
              end
              M_CMD0: launch(0,0,R_NONE,M_W0);
              M_W0: if(cmd_done) begin gap_clocks<=0;state<=M_GAP;end
              M_GAP: if(rise_tick) begin
                  if(gap_clocks==7) state<=M_CMD8;
                  else gap_clocks<=gap_clocks+1'b1;
              end
              M_CMD8: launch(8,32'h000001aa,R_R7,M_W8);
              M_W8: if(cmd_done) begin
                  if(cmd_error==1 || (cmd_error==0 && response_payload[22])) begin
                      legacy_card<=1;state<=M_CMD55;
                  end else if(cmd_error!=0) begin error<=cmd_error;state<=M_FAIL;end
                  else if(response_payload[11:0]!=12'h1aa) begin error<=7;state<=M_FAIL;end
                  else state<=M_CMD55;
              end
              M_CMD55: launch(55,0,R_R1,M_W55);
              M_W55: if(cmd_done) begin
                  if(cmd_error!=0) begin error<=cmd_error;state<=M_FAIL;end
                  else if(!response_payload[5]) begin error<=3;state<=M_FAIL;end
                  else state<=M_ACMD41;
              end
              M_ACMD41: launch(41,legacy_card ? 32'h00ff8000 : 32'h40ff8000,R_R3,M_W41);
              M_W41: if(cmd_done) begin
                  if(cmd_error!=0) begin error<=cmd_error;state<=M_FAIL;end
                  else if(response_payload[31]) begin
                      high_capacity<=response_payload[30];state<=M_CMD2;
                  end else if(init_attempt>=INIT_RETRIES) begin error<=8;state<=M_FAIL;end
                  else begin init_attempt<=init_attempt+1'b1;state<=M_CMD55;end
              end
              M_CMD2: launch(2,0,R_R2,M_W2);
              M_W2: if(cmd_done) begin
                  if(cmd_error!=0) begin error<=cmd_error;state<=M_FAIL;end
                  else state<=M_CMD3;
              end
              M_CMD3: launch(3,0,R_R6,M_W3);
              M_W3: if(cmd_done) begin
                  if(cmd_error!=0 || response_payload[31:16]==0) begin
                      error<=cmd_error!=0 ? cmd_error : 4'd3;state<=M_FAIL;
                  end else begin rca<=response_payload[31:16];state<=M_CMD7;end
              end
              M_CMD7: launch(7,{rca,16'h0000},R_R1B,M_W7);
              M_W7: if(cmd_done) begin
                  if(cmd_error!=0) begin error<=cmd_error;state<=M_FAIL;end
                  else state<=M_BUS55;
              end
              M_BUS55: launch(55,{rca,16'h0000},R_R1,M_WBUS55);
              M_WBUS55: if(cmd_done) begin
                  if(cmd_error!=0 || !response_payload[5]) begin
                      error<=cmd_error!=0 ? cmd_error : 4'd3;state<=M_FAIL;
                  end else state<=M_BUS6;
              end
              M_BUS6: launch(6,2,R_R1,M_WBUS6);
              M_WBUS6: if(cmd_done) begin
                  if(cmd_error!=0) begin error<=cmd_error;state<=M_FAIL;end
                  else if(!high_capacity) state<=M_CMD16;
                  else begin initialized<=1;busy<=0;fast_clock<=1;state<=M_READY;end
              end
              M_CMD16: launch(16,512,R_R1,M_W16);
              M_W16: if(cmd_done) begin
                  if(cmd_error!=0) begin error<=cmd_error;state<=M_FAIL;end
                  else begin initialized<=1;busy<=0;fast_clock<=1;state<=M_READY;end
              end
              M_READY: if(start) begin
                  error<=0;stop_for_error<=0;
                  if(blocks==0 || (!high_capacity && lba[31:23]!=0)) begin
                      error<=6;done<=1;
                  end else begin
                      read_lba<=lba;read_blocks<=blocks;busy<=1;state<=M_READ;
                  end
              end
              M_READ: begin
                  launch(18,high_capacity ? read_lba : (read_lba<<9),R_R1,M_WREAD);
                  data_go<=1;
              end
              M_WREAD: if(cmd_done) begin
                  if(cmd_error!=0) begin
                      error<=cmd_error;data_abort<=1;stop_for_error<=1;state<=M_STOP;
                  end else state<=M_READING;
              end
              M_READING: begin
                  if(data_error!=0) begin
                      error<=data_error;data_abort<=1;stop_for_error<=1;state<=M_STOP;
                  end else if(data_done) state<=M_STOP;
              end
              M_STOP: launch(12,0,R_R1B,M_WSTOP);
              M_WSTOP: if(cmd_done) begin
                  if(cmd_error!=0 && !stop_for_error) error<=cmd_error;
                  busy<=0;done<=1;state<=M_READY;
              end
              M_FAIL: begin initialized<=0;busy<=0;end
              default: state<=M_FAIL;
            endcase
        end
    end
    assign debug_status={state,command,command_state,cmd_error,data_error,initialized,busy,fast_clock,cmd_in,sd_dat};
    assign debug_data={state,data_state,nibble_count,valid,ready,sd_clk,data_done,cmd_error,data_error,pause_clock};
endmodule
