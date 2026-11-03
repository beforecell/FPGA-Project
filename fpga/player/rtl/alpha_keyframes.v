// Runtime bookmarks,not codec I-frames. Up to4 sorted source-frame IDs per
// catalog asset,held in volatile FPGA RAM. No TF writes. Reset/rescan clears.
// One shared comparator/word shifter. List is valid only while ready;the
// top mailbox holds its previous complete snapshot while a list is edited.
module alpha_keyframes #(parameter SHARED_RAM=0)(input clk,rst,input[3:0]asset,input enabled,frame_valid,
 input[15:0]displayed_frame,frame_count,input mark,backward,remove,
 output ready,output[2:0]count,output[63:0]frames,
 output reg seek,output reg[15:0]seek_frame,output reg beep,output reg[1:0]beep_kind,
 output reg[2:0]last_action,output reg[3:0]last_result,output reg[7:0]generation,
 output ram_we,ram_re,output[6:0]ram_wa,ram_ra,output[15:0]ram_din,input[15:0]ram_q);
 localparam INIT=0,IDLE=1,LOAD_ISSUE=2,LOAD_WAIT=3,SCAN=4,SHIFT_INSERT=5,SHIFT_DELETE=6,SAVE=7;
 localparam OK=0,FULL=1,DUPLICATE=2,NO_PREVIOUS=3,BUSY=4,INVALID=5;
 reg[3:0]state,asset_q,init_asset;reg loaded;
 reg[2:0]n,work_count,index,position;reg[1:0]operation;
 reg[15:0]at;reg[63:0]published;reg found;
 wire[6:0]base={asset_q,2'b00}+{3'd0,asset_q};
 wire[1:0]read_slot=state==SHIFT_INSERT?index[1:0]-2'd1:state==SHIFT_DELETE?index[1:0]+2'd1:index[1:0];
 wire[15:0]word=published[read_slot*16+:16];
 reg pub_we,pub_clear;reg[15:0]pub_data;
 // All cache mutations share one16-bit write bus and one read mux. Loading
 // reads the count first,so unused/uninitialized RAM words are never exposed.
 always @*begin
  pub_clear=state==IDLE&&(!loaded||asset!=asset_q);pub_we=0;pub_data=0;
  if(state==LOAD_WAIT&&index!=4)begin pub_we=1;pub_data=q;end
  else if(state==SHIFT_INSERT)begin pub_we=1;pub_data=index==position?at:word;end
  else if(state==SHIFT_DELETE)begin pub_we=1;pub_data=index+1'b1==n?16'd0:word;end
 end
 always @(posedge clk)begin
  if(rst||pub_clear)published<=0;
  else if(pub_we)case(index[1:0])
   0:published[15:0]<=pub_data;1:published[31:16]<=pub_data;
   2:published[47:32]<=pub_data;3:published[63:48]<=pub_data;
  endcase
 end
 reg we,re;reg[6:0]wa,ra;reg[15:0]din;wire[15:0]q;
 always @*begin
  we=0;re=0;wa=0;ra=0;din=0;
  if(state==INIT)begin we=1;wa=({init_asset,2'b00}+init_asset)+7'd4;end
  if(state==LOAD_ISSUE)begin re=1;ra=base+index;end
  if(state==SAVE)begin we=1;wa=base+index;din=index==4?{13'd0,work_count}:word;end
 end
 assign ram_we=we;assign ram_re=re;assign ram_wa=wa;assign ram_ra=ra;assign ram_din=din;
 generate if(SHARED_RAM)begin:shared_storage
  assign q=ram_q;
 end else begin:private_storage
  bb3_sdp_ram #(.WIDTH(16),.AW(7),.DEPTH(128),.IMPLEMENT("32K")) storage(clk,we,wa,din,re,ra,q);
 end endgenerate
 assign ready=state==IDLE&&loaded&&asset==asset_q;
 assign count=loaded&&asset==asset_q?n:3'd0;
 assign frames=loaded&&asset==asset_q?published:64'd0;
 task feedback;input[3:0]result;begin last_result<=result;beep<=1;beep_kind<=result==OK?2'd0:2'd3;end endtask
 always @(posedge clk)begin
  if(rst)begin state<=INIT;asset_q<=0;init_asset<=0;loaded<=0;n<=0;work_count<=0;index<=0;position<=0;operation<=0;at<=0;found<=0;seek<=0;seek_frame<=0;beep<=0;beep_kind<=0;last_action<=0;last_result<=0;generation<=0;end
  else begin
   seek<=0;beep<=0;
   if((mark||backward||remove)&&!ready)begin last_action<=mark?1:backward?2:3;feedback(BUSY);end
   case(state)
    INIT:if(init_asset==15)state<=IDLE;else init_asset<=init_asset+1'b1;
    IDLE:begin
     if(!loaded||asset!=asset_q)begin asset_q<=asset;loaded<=0;index<=4;state<=LOAD_ISSUE;end
     else if(mark||backward||remove)begin
      last_action<=mark?1:backward?2:3;
      if(!enabled||!frame_valid||frame_count==0||displayed_frame>=frame_count)feedback(INVALID);
      else begin operation<=mark?1:backward?2:3;at<=displayed_frame;index<=0;position<=0;found<=0;work_count<=n;state<=SCAN;end
     end
    end
    LOAD_ISSUE:state<=LOAD_WAIT;
    LOAD_WAIT:begin
     if(index==4)begin
      n<=q<=4?q[2:0]:3'd0;
      if(q==0||q>4)begin loaded<=1;generation<=generation+1'b1;state<=IDLE;end
      else begin index<=0;state<=LOAD_ISSUE;end
     end
     else if(index+1'b1==n)begin loaded<=1;generation<=generation+1'b1;state<=IDLE;end
     else begin index<=index+1'b1;state<=LOAD_ISSUE;end
    end
    SCAN:begin
     if(operation==1)begin
      if(index<n&&word==at)begin feedback(DUPLICATE);state<=IDLE;end
      else if(index==n||word>at)begin
       if(n==4)begin feedback(FULL);state<=IDLE;end
       else begin position<=index;index<=n;work_count<=n+1'b1;state<=SHIFT_INSERT;end
      end else index<=index+1'b1;
     end else if(index==n)begin
      if(!found)begin feedback(NO_PREVIOUS);state<=IDLE;end
      else if(operation==2)begin seek<=1;seek_frame<=published[position[1:0]*16+:16];feedback(OK);state<=IDLE;end
      else begin index<=position;work_count<=n-1'b1;state<=SHIFT_DELETE;end
     end else begin
      if(operation==2?word<at:word<=at)begin position<=index;found<=1;end
      index<=index+1'b1;
     end
    end
    SHIFT_INSERT:begin
     if(index==position)begin index<=0;state<=SAVE;end
     else index<=index-1'b1;
    end
    SHIFT_DELETE:begin
     if(index+1'b1==n)begin index<=0;state<=SAVE;end
     else index<=index+1'b1;
    end
    SAVE:if(index==4)begin n<=work_count;generation<=generation+1'b1;feedback(OK);state<=IDLE;end else index<=index+1'b1;
    default:state<=INIT;
   endcase
  end
 end
endmodule
