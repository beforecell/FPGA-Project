// Four pixel clocks input->output: packed-mask synchronous query takes two
// clocks; RGB, sync and metadata follow exactly the same delay, followed by
// two shader stages (character selection, then glyph). Processing
// always analyzes current/history; the displayed plane uses the matching ID.
module bb_video_process #(parameter ANALYSIS_ENABLE=1)(input clk,rst,frame_start,hs,vs,de,input[23:0]rgb,prev_rgb,
 input[9:0]screen_x,source_x,input[8:0]screen_y,source_y,input primary,
 input[31:0]frame_id,timestamp_ms,input frame_valid,history_valid,raw_mode,crc_ok,quad_mode,
 input[7:0]threshold,input[1:0]gamma,input[15:0]rate_q8_8,input[3:0]error,input[5:0]cache_ready,
 input playing,auto_slow,camera_mode,diagnostic,input[71:0]boot_diag,input[1:0]menu,input[15:0]frame_count,media_fps,
 input[31:0]late_count,input underflow_event,
 input clear_alarm,crc_alarm,input[31:0]crc_alarm_frame,
 output ohs,ovs,ode,output[23:0]out_rgb,output alarm,
 output[31:0]locked_event_frame,energy,output[18:0]motion_count,output summary_valid,
 output[31:0]display_id,display_time,underflows,display_updates,detector_skips,
 output[15:0]new_fps,hdmi_fps);
 reg[3:0]vsdelay;wire frame_tick=vsdelay[3];
 always @(posedge clk)if(rst)vsdelay<=0;else vsdelay<={vsdelay[2:0],frame_start};
 wire[31:0]history_id=frame_id==0?{16'd0,frame_count}-1'b1:frame_id-1'b1;
 wire dh,dm,mask;wire[3:0]bv;wire[111:0]boxes;wire[1:0]scene;
 wire[31:0]summary_id;wire event_pulse,detector_busy;
 wire[8:0]qx=screen_x[8:0];wire[7:0]qy=screen_y-240;
 generate if(ANALYSIS_ENABLE)begin:analysis
 bb3_motion_engine motion(clk,rst,frame_tick,frame_id,timestamp_ms,history_id,frame_valid,history_valid,raw_mode,
  quad_mode&&!raw_mode,de,screen_x,screen_y,rgb,prev_rgb,threshold,camera_mode,
  de&&quad_mode&&!raw_mode&&screen_x<320&&screen_y>=240,qx,qy,
  mask,dh,dm,display_id,display_time,bv,boxes,scene,energy,motion_count,summary_valid,summary_id,event_pulse,detector_skips,detector_busy);
 end else begin:clean_display
  assign mask=0;assign dh=0;assign dm=0;assign bv=0;assign boxes=0;assign scene=0;
  assign display_id=frame_id;assign display_time=timestamp_ms;assign energy=0;assign motion_count=0;
  assign summary_valid=frame_tick;assign summary_id=frame_id;assign event_pulse=0;assign detector_skips=0;assign detector_busy=0;
 end endgenerate
 reg alarm_hold;reg[31:0]locked;
 assign alarm=!clear_alarm&&(alarm_hold||crc_alarm||event_pulse);
 assign locked_event_frame=alarm_hold?locked:crc_alarm?crc_alarm_frame:event_pulse?summary_id:locked;
 always @(posedge clk)begin
  if(rst)begin alarm_hold<=0;locked<=0;end
  else if(clear_alarm)begin alarm_hold<=0;locked<=0;end
  else if(!alarm_hold&&(crc_alarm||event_pulse))begin alarm_hold<=1;locked<=crc_alarm?crc_alarm_frame:summary_id;end
 end
 reg[24:0]seconds;reg[8:0]new_count,refresh_count;reg[15:0]nf,hf;
 reg[31:0]uf,updates,last_display;reg display_seen;
 assign new_fps=nf;assign hdmi_fps=hf;assign underflows=uf;assign display_updates=updates;
 wire new_display=frame_valid&&!raw_mode&&(!display_seen||last_display!=display_id);
 always @(posedge clk)begin
  if(rst)begin seconds<=0;new_count<=0;refresh_count<=0;nf<=0;hf<=0;uf<=0;updates<=0;last_display<=0;display_seen<=0;end
  else begin
   if(underflow_event)uf<=uf+1'b1;
   if(frame_tick)refresh_count<=refresh_count+1'b1;
   if(new_display)begin last_display<=display_id;display_seen<=1;new_count<=new_count+1'b1;updates<=updates+1'b1;end
   if(seconds==24999999)begin seconds<=0;nf<={new_count[7:0],8'd0};hf<={refresh_count[7:0],8'd0};new_count<=new_display?1:0;refresh_count<=frame_tick?1:0;end
   else seconds<=seconds+1'b1;
  end
 end
 wire[23:0]chosen=dh?prev_rgb:rgb;wire nhs,nvs,nde;wire[23:0]night;
 bb_night_gamma enhance(clk,rst,hs,vs,de,chosen,gamma,nhs,nvs,nde,night);
 reg[23:0]p0,p1,night1;reg[9:0]x0,x1;reg[8:0]y0,y1;reg[2:0]sync0,sync1;
 always @(posedge clk)begin
  if(rst)begin p0<=0;p1<=0;night1<=0;x0<=0;x1<=0;y0<=0;y1<=0;sync0<=0;sync1<=0;end
  else begin p0<=chosen;p1<=p0;night1<=night;x0<=screen_x;x1<=x0;y0<=screen_y;y1<=y0;sync0<={hs,vs,de};sync1<=sync0;end
 end
 bb_forensic_osd shader(clk,rst,sync1[2],sync1[1],sync1[0],x1,y1,p1,night1,quad_mode,raw_mode,mask,
  bv,boxes,scene,playing,auto_slow,diagnostic,alarm,crc_ok,menu,boot_diag,error,display_id,display_time,frame_count,media_fps,new_fps,hdmi_fps,rate_q8_8,
  threshold,gamma,cache_ready,energy,underflows,late_count,motion_count,ohs,ovs,ode,out_rgb);
endmodule
