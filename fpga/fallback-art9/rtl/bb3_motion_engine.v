// Layout-independent binary motion,3x3 denoise,4x4-cell occupancy and bounded
// component analysis. Two packed1-bit image banks, tagged with frame ID, are
// the only full-picture stores. No expanded RGB framebuffer or CPU.
module bb3_motion_engine(input clk,rst,input frame_tick,
 input[31:0]frame_id,timestamp_ms,history_id,input frame_valid,history_valid,raw_mode,
 input quad_mode,de,input[9:0]x,input[8:0]y,input[23:0]rgb,previous,
 input[7:0]threshold,input camera_mode,
 input query_en,input[8:0]query_x,input[7:0]query_y,
 output reg query_bit,output reg display_history,display_mask_valid,
 output reg[31:0]display_id,display_time,output reg[3:0]display_boxes_valid,
 output reg[111:0]display_boxes,output reg[1:0]display_scene,
 output reg[31:0]energy,output reg[18:0]motion_count,output reg summary_valid,
 output reg[31:0]summary_id,output reg event_pulse,output reg[31:0]skipped,
 output wire busy);
 wire analysis_reset=rst||raw_mode||!frame_valid;
 wire rv;wire[8:0]rx;wire[7:0]ry;wire[23:0]rc,rp;
 bb3_reduce2 reduce(clk,analysis_reset,frame_valid&&!raw_mode,quad_mode,de,x,y,rgb,previous,rv,rx,ry,rc,rp);
 reg running,write_bank,display_bank,done_seen;reg[31:0]last_done,work_id,work_time;
 reg[7:0]work_threshold;reg work_camera,work_history;
 reg[2:0]state;localparam IDLE=0,CAPTURE=1,START_CCL=2,WAIT_CCL=3,COMMIT=4,FILTER_START=5,FILTER_WAIT=6,WAIT_GRID=7;
 wire begin_frame=rv&&rx==0&&ry==0&&state==IDLE&&(!done_seen||last_done!=frame_id||work_threshold!=threshold||work_camera!=camera_mode);
 wire sample=rv&&(running||begin_frame);
 wire[15:0]cs=rc[23:16]*16'd77+rc[15:8]*16'd150+rc[7:0]*16'd29;
 wire[15:0]ps=rp[23:16]*16'd77+rp[15:8]*16'd150+rp[7:0]*16'd29;
 wire[7:0]delta=cs[15:8]>ps[15:8]?cs[15:8]-ps[15:8]:ps[15:8]-cs[15:8];
 wire hist=begin_frame?history_valid:work_history;
 wire mv,mb,meof;wire[8:0]mx;wire[7:0]my;
 bb3_majority denoise(clk,analysis_reset,sample,rx,ry,hist&&delta>(begin_frame?threshold:work_threshold),
  begin_frame?camera_mode:work_camera,mv,mx,my,mb,meof);
 reg[31:0]energy_acc,gray_c,gray_p;reg[18:0]raw_count,filtered_count;
 wire[31:0]mean_gap=gray_c>gray_p?gray_c-gray_p:gray_p-gray_c;
 wire lighting=raw_count>19200&&mean_gap>1536000;
 wire camera_global=work_camera&&filtered_count>23040;
 reg[1:0]scene;
 // One-cycle cell accumulation stage, with same-address forwarding.
 // Small random-access column state belongs in BRAM, not400 flip-flops.
 reg mv1,mb1,meof1;reg[8:0]mx1;reg[7:0]my1;
 wire[6:0]cell_x=mx1[8:2];wire[4:0]count_q;
 reg forwarded;reg[6:0]forward_x;reg[4:0]forward_count;
 wire[4:0]count_before=mx1[1:0]==0&&my1[1:0]==0?5'd0:
   forwarded&&forward_x==cell_x?forward_count:count_q;
 wire[4:0]count_next=count_before+mb1;
 wire count_we=mv1&&state==CAPTURE&&!analysis_reset;
 bb3_sdp_ram #(.WIDTH(5),.AW(7),.DEPTH(128)) counts(clk,count_we,cell_x,count_next,mv,mx[8:2],count_q);
 always @(posedge clk)begin
  if(analysis_reset)begin mv1<=0;mb1<=0;meof1<=0;mx1<=0;my1<=0;forwarded<=0;forward_x<=0;forward_count<=0;end
  else begin
   mv1<=mv;if(mv)begin mb1<=mb;meof1<=meof;mx1<=mx;my1<=my;end
   forwarded<=count_we;if(count_we)begin forward_x<=cell_x;forward_count<=count_next;end
  end
 end
 reg cell_we,cell_bit;reg[12:0]cell_addr,active_cells;
 wire cdone,cbusy,overflow;wire[3:0]cvalid;wire[111:0]cboxes;
 wire tv,tb,dv,db,cv,cb;wire[12:0]ta,da,ca;
 bb3_grid_history #(.FRAMES(2)) temporal(clk,analysis_reset,1'b0,begin_frame,
  done_seen&&frame_id==last_done+1'b1,cell_we,cell_addr,cell_bit,tv,ta,tb);
 bb3_grid_morph dilate(clk,analysis_reset,tv,ta,tb,dv,da,db);
 bb3_grid_morph #(.ERODE(1)) erode(clk,analysis_reset,dv,da,db,cv,ca,cb);
 bb3_components #(.CONNECTIVITY(8)) components(clk,analysis_reset,cv,ca,cb,state==START_CCL,
  scene!=0,active_cells,cbusy,cdone,overflow,cvalid,cboxes);
 wire filter_done;wire[3:0]filtered_valid;wire[111:0]filtered_boxes;
 bb_target_boxes box_filter(clk,analysis_reset,state==FILTER_START,done_seen&&work_id==last_done+1'b1,cvalid,cboxes,filter_done,filtered_valid,filtered_boxes);
 reg[13:0]word_index;reg[3:0]phase;reg[8:0]packed_bits;
 wire[8:0]packed_next=packed_bits | ({8'd0,mb}<<phase);
 wire mask_we=mv&&(phase==8||meof);
 wire[16:0]linear=query_y*17'd320+query_x;
 wire[13:0]qa=linear/9;wire[3:0]qb=linear%9;
 wire[8:0]mq0,mq1;reg[3:0]qbit;reg qbank,qvalid;
 bb3_paged_ram mask0(clk,mask_we&&!write_bank,word_index,packed_next,query_en,qa,mq0);
 bb3_paged_ram mask1(clk,mask_we&&write_bank,word_index,packed_next,query_en,qa,mq1);
 reg[1:0]ready;reg[31:0]id0,id1,time0,time1;reg[111:0]boxes0,boxes1;reg[3:0]valids0,valids1;reg[1:0]scene0,scene1;
 wire c0=ready[0]&&id0==frame_id,c1=ready[1]&&id1==frame_id;
 wire h0=ready[0]&&id0==history_id,h1=ready[1]&&id1==history_id;
 wire found_current=c0||c1;
 wire found_history=history_valid&&(h0||h1);
 wire chosen=found_current?c1:h1;
 assign busy=state!=IDLE;
 always @(posedge clk)begin
  if(analysis_reset)begin
   running<=0;write_bank<=0;display_bank<=0;done_seen<=0;last_done<=0;work_id<=0;work_time<=0;
   work_threshold<=0;work_camera<=0;work_history<=0;state<=IDLE;energy_acc<=0;gray_c<=0;gray_p<=0;
   raw_count<=0;filtered_count<=0;scene<=0;cell_we<=0;cell_bit<=0;cell_addr<=0;active_cells<=0;
   word_index<=0;phase<=0;packed_bits<=0;ready<=0;qbit<=0;qbank<=0;qvalid<=0;query_bit<=0;
   display_history<=0;display_mask_valid<=0;display_id<=0;display_time<=0;display_boxes_valid<=0;display_boxes<=0;display_scene<=0;
   energy<=0;motion_count<=0;summary_valid<=0;summary_id<=0;event_pulse<=0;skipped<=0;
  end else begin
   cell_we<=0;summary_valid<=0;event_pulse<=0;
   if(query_en)begin qbit<=qb;qbank<=display_bank;end
   qvalid<=query_en&&display_mask_valid;
   query_bit<=qvalid&&(qbank?mq1[qbit]:mq0[qbit]);
   if(frame_tick)begin
    display_history<=!raw_mode&&!found_current&&found_history;
    display_mask_valid<=!raw_mode&&(found_current||found_history);
    display_id<=!raw_mode&&!found_current&&found_history?history_id:frame_id;
    display_time<=!raw_mode&&(found_current||found_history)?(chosen?time1:time0):timestamp_ms;
    if(!raw_mode&&(found_current||found_history))begin
     display_bank<=chosen;display_boxes<=(chosen?boxes1:boxes0);display_boxes_valid<=(chosen?valids1:valids0);display_scene<=(chosen?scene1:scene0);
    end else begin display_boxes_valid<=0;display_scene<=0;end
    if(state!=IDLE&&frame_id!=work_id)skipped<=skipped+1'b1;
   end
   if(begin_frame)begin
    running<=1;state<=CAPTURE;write_bank<=!display_bank;ready[!display_bank]<=0;
    work_id<=frame_id;work_time<=timestamp_ms;work_threshold<=threshold;work_camera<=camera_mode;work_history<=history_valid;
    energy_acc<=hist?{24'd0,delta}:0;gray_c<=cs[15:8];gray_p<=ps[15:8];raw_count<=hist&&delta>threshold?1:0;
    filtered_count<=0;word_index<=0;phase<=0;packed_bits<=0;active_cells<=0;
   end else if(sample)begin
    if(hist)begin energy_acc<=energy_acc+delta;if(delta>work_threshold)raw_count<=raw_count+1'b1;end
    gray_c<=gray_c+cs[15:8];gray_p<=gray_p+ps[15:8];
   end
   if(sample&&rx==319&&ry==239)running<=0;
   if(mv1&&state==CAPTURE)begin
    if(mb1)filtered_count<=filtered_count+1'b1;
    if(mx1[1:0]==3&&my1[1:0]==3)begin
     cell_addr<=my1[7:2]*13'd80+cell_x;cell_bit<=count_next>=(work_camera?8:3);cell_we<=1;
    end
    if(meof1)begin state<=WAIT_GRID;scene<=lighting?2'd1:camera_global?2'd2:2'd0;end
   end
   if(mv&&state==CAPTURE)begin
    if(phase==8)begin phase<=0;packed_bits<=0;word_index<=word_index+1'b1;end
    else begin phase<=phase+1'b1;packed_bits<=packed_next;end
   end
   if(cv)begin
    if(cb)active_cells<=active_cells+1'b1;
    if(ca==4799)begin state<=START_CCL;if(active_cells>2400)scene<=2;end
   end
   if(state==START_CCL)state<=WAIT_CCL;
   if(state==WAIT_CCL&&cdone)state<=FILTER_START;
   if(state==FILTER_START)state<=FILTER_WAIT;
   if(state==FILTER_WAIT&&filter_done)state<=COMMIT;
   if(state==COMMIT)begin
    // Two-entry metadata stays in explicit flip-flops, rather than tiny
    // inferred distributed RAM with a short write-data hold path.
    ready[write_bank]<=1;
    if(write_bank)begin id1<=work_id;time1<=work_time;boxes1<=filtered_boxes;valids1<=scene!=0||overflow?4'd0:filtered_valid;scene1<=overflow?2'd3:scene;end
    else begin id0<=work_id;time0<=work_time;boxes0<=filtered_boxes;valids0<=scene!=0||overflow?4'd0:filtered_valid;scene0<=overflow?2'd3:scene;end
    last_done<=work_id;done_seen<=1;energy<=energy_acc;motion_count<=filtered_count;summary_id<=work_id;summary_valid<=1;
    event_pulse<=work_history&&energy_acc>6000000;state<=IDLE;
   end
  end
 end
endmodule
