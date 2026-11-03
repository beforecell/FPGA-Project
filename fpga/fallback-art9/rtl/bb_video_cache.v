// Two compressed row-group caches per current/history plane. Native BC1 uses
// 160 64-bit blocks per four source rows; raw photo mode uses 320 packed565
// words per source row. No expanded framebuffer and no quadrant image copies.
module bb_video_cache(
 input clk,rst,frame_start,hs,vs,de,quad_mode,
 input pub_req_toggle,input [20:0] pub_cur_base,pub_hist_base,
 input [31:0] pub_frame_id,pub_timestamp_ms,input pub_raw,pub_valid,pub_history,pub_crc,
 output reg pub_ack_toggle,pub_accepted,
 output reg [31:0] frame_id,timestamp_ms,output reg raw_mode,frame_valid,history_valid,crc_ok,
 output reg rd_req_toggle,output reg [20:0] cur_base,hist_base,
 output [9:0] rd_words,output reg history_enable,input rd_done_toggle,
 output cur_pop,hist_pop,input [31:0] cur_data,hist_data,input cur_valid,cur_empty,hist_valid,hist_empty,
 output reg ohs,ovs,ode,output reg [23:0] rgb,prev_rgb,
 output reg [9:0] screenx,sourcex,output reg [8:0] screeny,sourcey,
 output reg primary,output reg underflow,output reg underflow_event,output filling_busy,
 input hold_photo,input[20:0]hold_base
);
 reg [47:0] current_cache[0:1023],history_cache[0:1023];
 reg [47:0] cq,hq;reg [31:0] cur_lo,hist_lo;reg [15:0] cur_mid,hist_mid;
 reg [1:0] cphase,hphase;reg [8:0] cblock,hblock;reg qquad;
 reg [9:0] x;reg [8:0] y;reg last_de;
 wire [9:0] local_x=x>=320?x-320:x;
 wire [8:0] local_y=y>=240?y-240:y;
 wire is_quad=quad_mode&&!raw_mode;
 wire [9:0] sx=is_quad?{local_x[8:0],1'b0}:x;
 wire [8:0] sy=is_quad?{local_y[7:0],1'b0}:y;
 wire [8:0] row_tag=raw_mode?9'd479-sy:{1'b0,sy[8:1]};
 reg [8:0] tag0,tag1;reg [1:0] cache_valid;
 wire render_bank=cache_valid[1]&&tag1==row_tag;
 wire hit=(cache_valid[0]&&tag0==row_tag)||(cache_valid[1]&&tag1==row_tag);
 wire [8:0] column=raw_mode?{1'b0,sx[9:1]}:{1'b0,sx[9:2]};
 wire [9:0] render_address={render_bank,column};
 reg bootstrap;reg filling,fill_bank;reg [8:0] fill_tag;
 assign filling_busy=filling;
 reg [9:0] ci,hi,cr,hr;
 reg [15:0] fill_timer;reg [1:0] prime;
 reg [20:0] active_cur,active_hist;
 (* async_reg="true" *)reg [2:0] req_sync,done_sync;
 (* async_reg="true" *)reg [109:0] meta0,meta1;
 reg [109:0] pending_meta;reg pending;
 reg [8:0] last_render_tag;
 reg qhs,qvs,qde,qprimary,qhit,qraw;
 reg [9:0] qx,qsx;reg [8:0] qy,qsy;
 assign rd_words=raw_mode?10'd320:10'd240;
 assign cur_pop=filling&&ci<rd_words&&!cur_empty;
 assign hist_pop=filling&&history_enable&&hi<rd_words&&!hist_empty;
 wire cur_write=cur_valid&&filling&&(raw_mode||cphase!=0);
 wire hist_write=hist_valid&&filling&&(raw_mode||hphase!=0);
 wire [9:0] cur_write_addr={fill_bank,raw_mode?cr[8:0]:cblock};
 wire [9:0] hist_write_addr={fill_bank,raw_mode?hr[8:0]:hblock};
 always @(posedge clk)begin
  if(cur_write)current_cache[cur_write_addr]<=raw_mode?{16'd0,cur_data}:cphase==1?{cur_data[15:0],cur_lo}:{cur_data,cur_mid};
  if(hist_write)history_cache[hist_write_addr]<=raw_mode?{16'd0,hist_data}:hphase==1?{hist_data[15:0],hist_lo}:{hist_data,hist_mid};
  cq<=current_cache[render_address];hq<=history_cache[render_address];
 end
 wire [23:0] bc_rgb,bc_prev;
 wire [15:0] unused565a,unused565b;
 bc1_block_pixel dec_cur(cq[31:0],{16'd0,cq[47:32]},qsx[1:0],{1'b0,qsy[0]},unused565a,bc_rgb);
 bc1_block_pixel dec_hist(hq[31:0],{16'd0,hq[47:32]},qsx[1:0],{1'b0,qsy[0]},unused565b,bc_prev);
 wire [23:0] area_rgb,area_prev;
 bb48_area_pixel area_cur(cq[31:0],cq[47:32],qsx[1],area_rgb);
 bb48_area_pixel area_hist(hq[31:0],hq[47:32],qsx[1],area_prev);
 wire [15:0] photo_pixel=qsx[0]?cq[31:16]:cq[15:0];
 wire[15:0]old_photo_pixel=qsx[0]?hq[31:16]:hq[15:0];
 wire[23:0]old_photo_rgb={old_photo_pixel[15:11],old_photo_pixel[15:13],old_photo_pixel[10:5],old_photo_pixel[10:9],old_photo_pixel[4:0],old_photo_pixel[4:2]};
 wire [23:0] photo_rgb={photo_pixel[15:11],photo_pixel[15:13],photo_pixel[10:5],photo_pixel[10:9],photo_pixel[4:0],photo_pixel[4:2]};
 task fetch_row;
  input [8:0] tag;input bank;
  begin
   cur_base<=active_cur+tag*(raw_mode?21'd320:21'd240);hist_base<=active_hist+tag*(raw_mode?21'd320:21'd240);
   history_enable<=history_valid;
   rd_req_toggle<=~rd_req_toggle;filling<=1;fill_bank<=bank;fill_tag<=tag;
   ci<=0;hi<=0;cr<=0;hr<=0;cphase<=0;hphase<=0;cblock<=0;hblock<=0;fill_timer<=0;cache_valid[bank]<=0;
  end
 endtask
 function [8:0] following;
  input [8:0] tag;input raw,quad;
  begin
   if(!raw)following=tag==239?0:tag+1'b1;
   else if(quad)following=tag<=1?9'd479:tag-2;
   else following=tag==0?9'd479:tag-1'b1;
  end
 endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   bootstrap<=1;x<=0;y<=0;last_de<=0;tag0<=0;tag1<=0;cache_valid<=0;cur_lo<=0;hist_lo<=0;
   filling<=0;fill_bank<=0;fill_tag<=0;ci<=0;hi<=0;cr<=0;hr<=0;fill_timer<=0;prime<=0;
   active_cur<=0;active_hist<=0;req_sync<=0;done_sync<=0;meta0<=0;meta1<=0;pending_meta<=0;pending<=0;
   pub_ack_toggle<=0;pub_accepted<=0;frame_id<=0;timestamp_ms<=0;raw_mode<=0;frame_valid<=0;history_valid<=0;crc_ok<=0;
   rd_req_toggle<=0;cur_base<=0;hist_base<=0;history_enable<=0;last_render_tag<=511;
   qhs<=0;qvs<=0;qde<=0;qprimary<=0;qhit<=0;qraw<=0;qquad<=0;qx<=0;qy<=0;qsx<=0;qsy<=0;
   cphase<=0;hphase<=0;cblock<=0;hblock<=0;cur_mid<=0;hist_mid<=0;underflow_event<=0;
   ohs<=0;ovs<=0;ode<=0;rgb<=0;prev_rgb<=0;screenx<=0;screeny<=0;sourcex<=0;sourcey<=0;primary<=0;underflow<=0;
  end else begin
   pub_accepted<=0;underflow_event<=0;
   if(bootstrap)begin
    bootstrap<=0;
    if(hold_photo)begin active_cur<=hold_base;active_hist<=hold_base;frame_id<=32'h80000000;raw_mode<=1;frame_valid<=1;crc_ok<=1;prime<=1;end
   end
   req_sync<={req_sync[1:0],pub_req_toggle};done_sync<={done_sync[1:0],rd_done_toggle};
   meta0<={pub_cur_base,pub_hist_base,pub_frame_id,pub_timestamp_ms,pub_raw,pub_valid,pub_history,pub_crc};meta1<=meta0;
   if(req_sync[2]!=pub_ack_toggle&&!pending)begin pending_meta<=meta1;pending<=1;end
   last_de<=de;
   if(!de)x<=0;else x<=x+1'b1;
   if(last_de&&!de)y<=y+1'b1;
   qhs<=hs;qvs<=vs;qde<=de;qx<=x;qy<=y;qsx<=sx;qsy<=sy;
   qprimary<=!is_quad||(x<320&&y<240);qhit<=hit&&frame_valid;qraw<=raw_mode;qquad<=is_quad;
   ohs<=qhs;ovs<=qvs;ode<=qde;screenx<=qx;screeny<=qy;sourcex<=qsx;sourcey<=qsy;primary<=qprimary;
   rgb<=qhit?(qraw?photo_rgb:qquad?area_rgb:bc_rgb):24'd0;
   prev_rgb<=qhit&&history_valid?(qraw?old_photo_rgb:qquad?area_prev:bc_prev):(qraw?photo_rgb:24'd0);
   if(frame_start)begin
    x<=0;y<=0;last_render_tag<=511;
    if(!filling)begin
     if(pending)begin
      {active_cur,active_hist,frame_id,timestamp_ms,raw_mode,frame_valid,history_valid,crc_ok}<=pending_meta;
      pub_ack_toggle<=req_sync[2];pending<=0;pub_accepted<=1;
     end
     cache_valid<=0;prime<=1;
    end
   end else if(prime==1&&!filling)begin
    if(frame_valid)begin fetch_row(raw_mode?9'd479:9'd0,1'b0);prime<=2;end else prime<=0;
   end else if(prime==3&&!filling)begin
    fetch_row(following(tag0,raw_mode,is_quad),1'b1);prime<=0;
   end else if(de&&!last_de&&frame_valid)begin
    if(!hit)begin underflow<=1;underflow_event<=1;end
    if(hit&&row_tag!=last_render_tag)begin
     last_render_tag<=row_tag;
     if(prime==0&&!filling && !(raw_mode ? y==479 : (is_quad ? y>=479 : y>=478)) &&
        !(cache_valid[!render_bank] && (render_bank?tag0:tag1)==following(row_tag,raw_mode,is_quad)))
      fetch_row(following(row_tag,raw_mode,is_quad),!render_bank);
    end
   end
   if(cur_pop)ci<=ci+1'b1;if(hist_pop)hi<=hi+1'b1;
   if(cur_valid&&filling)begin
    cur_lo<=cur_data;cr<=cr+1'b1;
    if(cphase==1)cur_mid<=cur_data[31:16];if(cphase!=0)cblock<=cblock+1'b1;cphase<=cphase==2?0:cphase+1'b1;
   end
   if(hist_valid&&filling)begin
    hist_lo<=hist_data;hr<=hr+1'b1;
    if(hphase==1)hist_mid<=hist_data[31:16];if(hphase!=0)hblock<=hblock+1'b1;hphase<=hphase==2?0:hphase+1'b1;
   end
   if(filling)begin
    fill_timer<=fill_timer+1'b1;
    if(fill_timer==16000)underflow<=1;
    if(cr==rd_words&&(!history_enable||hr==rd_words)&&done_sync[2]==rd_req_toggle)begin
     filling<=0;cache_valid[fill_bank]<=1;
     if(fill_bank)tag1<=fill_tag;else tag0<=fill_tag;
     if(prime==2)prime<=3;
    end
   end
  end
 end
endmodule
