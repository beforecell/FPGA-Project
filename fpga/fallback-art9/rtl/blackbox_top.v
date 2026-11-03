// HX4S20C original compressed-media replay architecture.
// Vendor reuse: PLL primitives, SDRAM physical core and HDMI packet/serializer.
module top(
 input clk,rst_n,key1,key2,key3,
 input [3:0] sw,input uart_rx,output uart_tx,output [3:0] led,
 output [7:0] seg_sel,seg_data,
 output HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,
 output HDMI_DDC_SCL,inout HDMI_DDC_SDA,
 output sd_dclk,inout sd_cmd,inout [3:0] sd_dat
);
 wire pll_feedback100,raw_mem_clk,raw_mem_sft,video_clk,serial_clk;
 wire control_clk=clk;
 wire sys_lock,video_lock,rst_all,rst_sys,rst_mem,rst_video,rst50;
 wire mem_clk,mem_clk_sft;
 wire board_reset;
 alpha_board_reset por(clk,{key2,key3,key1,rst_n},board_reset);
 assign rst_all=board_reset|~sys_lock|~video_lock;
 sys_pll sys_pll_m0(.refclk(clk),.reset(1'b0),.clk0_out(pll_feedback100),
  .clk1_out(raw_mem_clk),.clk2_out(raw_mem_sft),.extlock(sys_lock));
 video_pll video_pll_m0(.refclk(clk),.reset(1'b0),.clk0_out(video_clk),
  .clk1_out(serial_clk),.extlock(video_lock));
 wire raw_reset; bb_reset_release reset_raw(raw_mem_clk,rst_all,raw_reset);
 reg [1:0] mem_div;
 always @(posedge raw_mem_clk or posedge raw_reset)begin
  if(raw_reset)mem_div<=0;else mem_div<=mem_div+1'b1;
 end
 EG_LOGIC_BUFG bb_mem_bufg(.i(mem_div[1]),.o(mem_clk));
 assign mem_clk_sft=~mem_clk;
 bb_reset_release reset_sys(control_clk,rst_all,rst_sys);
 bb_reset_release reset_mem(mem_clk,rst_all,rst_mem);
 bb_reset_release reset_video(video_clk,rst_all,rst_video);
 bb_reset_release reset_board(clk,rst_all,rst50);


 wire adjust_mode;reg adjust_last;wire[3:0]short_key,long_key,repeat_key,repeat_mask;
 always @(posedge control_clk)if(rst_sys)adjust_last<=0;else adjust_last<=adjust_mode;
 wire[3:0]physical_repeat_mask=adjust_last!=adjust_mode ? 4'd0:repeat_mask;
 alpha_keys #(.CLK_HZ(50000000)) keys(control_clk,rst_sys,{key2,key3,key1,rst_n},short_key,long_key,physical_repeat_mask,repeat_key,{browser,image_asset,analysis_on,fullscreen,speed_mode,adjust_mode});
 wire[3:0]remote_short,remote_long;wire remote_scan;
 wire[7:0]exposure,contrast,brightness,local_volume;wire[1:0]adjust_item;wire local_volume_set,adjust_beep;
 alpha_adjust adjustments(control_clk,rst_sys,adjust_mode,short_key|remote_short,long_key|remote_long,repeat_key,
 volume_percent,adjust_item,exposure,contrast,brightness,local_volume_set,local_volume,adjust_beep);
 wire scan,pick,next_photo,prev_photo,browser,fullscreen,paused,muted,diagnostic,announcing;
 wire[3:0]selected;wire[1:0]focus,display_view,cue_index,beep_kind;wire cue_start,cue_cancel,beep,cue_done;
 wire photo_auto;wire[1:0]photo_period;wire opened;
 wire next_video,prev_video,step_next,step_prev,root_page,folder_images,speed_mode,analysis_on;
 wire[10:0]rate_q8_8;wire[47:0]list_map;wire[3:0]list_count,selected_row;
 wire seek_busy,seek_toggle,seek_audio,seek_ack;wire[15:0]seek_frame,seek_phase;wire[31:0]seek_sample,seek_ms;wire[5:0]seek_ms_phase;
 reg[10:0]old_rate;reg audio_rate_wait,saw_rate_flush;wire rate_event=old_rate!=rate_q8_8;
 always @(posedge control_clk)begin
  if(rst_sys)begin old_rate<=256;audio_rate_wait<=0;saw_rate_flush<=0;end
  else begin old_rate<=rate_q8_8;
   if(media_reset||browser)begin audio_rate_wait<=0;saw_rate_flush<=0;end
   else if(rate_event&&rate_q8_8==256)begin audio_rate_wait<=1;saw_rate_flush<=0;end
   else if(audio_rate_wait)begin if(!track_ready)saw_rate_flush<=1;if(saw_rate_flush&&track_ready&&!pcm_flush)audio_rate_wait<=0;end
  end
 end
 wire card_init,card_busy,card_done,card_valid,card_ready,card_start;
 wire[31:0]card_lba,card_blocks;wire[7:0]card_data;wire[3:0]card_error;
 wire[31:0]sd_debug,sd_data_debug;
 wire[2:0]request,client_busy,client_done,client_valid,client_ready;wire[3:0]err_catalog,err_audio,err_store;
 wire[31:0]catalog_lba,catalog_blocks,audio_card_lba,audio_card_blocks,store_card_lba,store_card_blocks;
 wire catalog_loaded,catalog_busy,selected_ready;wire[4:0]resource_count,total_count;wire[3:0]catalog_error,query_index;
 wire[1:0]selected_type;wire[31:0]q_lba,q_bytes,q_audio_lba,q_audio_samples,q_crc,q_duration;
 wire[15:0]q_width,q_height,q_fps,q_frames,valid_mask,image_mask;
 wire[31:0]c0_lba,c1_lba,c2_lba,c3_lba,c0_samples,c1_samples,c2_samples,c3_samples;
 wire[3:0]name_item;wire[4:0]name_char;wire[7:0]name_data;
 wire cache_frame_valid;wire media_reset,active_valid,image_asset,loading,manager_enable,audio_restart;
 wire[3:0]active_index;wire[31:0]asset_lba,asset_bytes,asset_crc,audio_lba,audio_samples,duration_ms;
 wire[15:0]asset_width,asset_height;
 wire mrst_sys,mrst_mem,mrst_video;
 reg photo_bank,photo_previous_bank,photo_previous_valid,photo_prepared,photo_backwards;
 wire photo_busy_video;(* async_reg="true" *)reg[1:0]photo_busy_sync;
 always @(posedge control_clk)begin
  if(rst_sys)begin photo_bank<=0;photo_previous_bank<=0;photo_previous_valid<=0;photo_prepared<=0;photo_backwards<=0;photo_busy_sync<=0;end
  else begin
   photo_busy_sync<={photo_busy_sync[0],photo_busy_video};
   if(prev_photo)photo_backwards<=1;else if(next_photo||auto_next||pick)photo_backwards<=0;
   if(opened)begin
    photo_previous_bank<=photo_bank;
    photo_previous_valid<=photo_prepared&&image_asset;
    photo_bank<=photo_prepared&&image_asset ? !photo_bank:0;
    photo_prepared<=0;
   end else if(boot_done&&image_asset)photo_prepared<=1;
   if(active_valid&&!image_asset)begin photo_prepared<=0;photo_previous_valid<=0;end
  end
 end
 wire[20:0]photo_destination=photo_bank ? 21'd153600:21'd0;
 wire[20:0]photo_previous=photo_previous_bank ? 21'd153600:21'd0;
 bb_reset_release media_rs(control_clk,rst_all|media_reset|!active_valid,mrst_sys);
 bb_reset_release media_rm(mem_clk,rst_all|media_reset|!active_valid,mrst_mem);
 bb_reset_release media_rv(video_clk,rst_all|media_reset|!active_valid,mrst_video);
 wire phy_busy,phy_done,phy_valid,phy_ready;wire[7:0]phy_data;wire[3:0]phy_error;
 alpha_sd_elastic sdqueue(control_clk,rst_sys|media_reset,phy_busy,phy_done,phy_valid,phy_data,phy_error,phy_ready,card_busy,card_done,card_valid,card_data,card_error,card_ready);
 sd_native4 transport(.clk(control_clk),.rst(rst_sys|media_reset),.start(card_start),.lba(card_lba),.blocks(card_blocks),.initialized(card_init),.busy(phy_busy),.done(phy_done),.error(phy_error),.data(phy_data),.valid(phy_valid),.ready(phy_ready),.debug_status(sd_debug),.debug_data(sd_data_debug),.sd_clk(sd_dclk),.sd_cmd(sd_cmd),.sd_dat(sd_dat));
 alpha_sd_arb sdarb(control_clk,rst_sys|media_reset,request,catalog_lba,audio_card_lba,store_card_lba,catalog_blocks,audio_card_blocks,store_card_blocks,client_ready,client_busy,client_done,client_valid,,err_catalog,err_audio,err_store,card_start,card_lba,card_blocks,card_busy,card_done,card_valid,card_data,card_error,card_ready);
 alpha_catalog catalog(.clk(control_clk),.rst(rst_sys),.scan(scan),.initialized(card_init),.card_busy(client_busy[0]),.card_done(client_done[0]),.card_valid(client_valid[0]),.card_data(card_data),.card_error(err_catalog),
 .start(request[0]),.lba(catalog_lba),.blocks(catalog_blocks),.ready(client_ready[0]),.loaded(catalog_loaded),.busy(catalog_busy),.error(catalog_error),.count(resource_count),.total_count(total_count),.selected(query_index),.selected_ready(selected_ready),.kind(selected_type),
 .asset_lba(q_lba),.asset_bytes(q_bytes),.audio_lba(q_audio_lba),.audio_samples(q_audio_samples),.asset_crc(q_crc),.duration_ms(q_duration),.width(q_width),.height(q_height),.fps(q_fps),.frame_count(q_frames),
 .cue0_lba(c0_lba),.cue1_lba(c1_lba),.cue2_lba(c2_lba),.cue3_lba(c3_lba),.cue0_samples(c0_samples),.cue1_samples(c1_samples),.cue2_samples(c2_samples),.cue3_samples(c3_samples),.valid_mask(valid_mask),.image_mask(image_mask),
 .name_clk(video_clk),.name_item(name_item),.name_char(name_char),.name_data(name_data));
 wire manager_idle;wire boot_done,store_busy,job_start,job_done,job_ok,header_valid;
 wire[1:0]job_kind;wire[15:0]job_index,frame_count,nominal_fps;wire[4:0]job_slot;
 wire[3:0]store_error,manager_error;wire[31:0]job_crc,job_expected,job_timestamp,bmp_lba,store_debug;wire[7:0]default_threshold;
 wire wr_req_toggle,wr_ack_toggle,wr_done_toggle,wr_valid,wr_ready;wire[20:0]wr_base;wire[19:0]wr_len;wire[31:0]wr_data;
 wire pub_req,pub_ack,pub_raw,pub_valid,pub_history,pub_crc;wire[20:0]pub_cur,pub_hist;wire[31:0]pub_frame,pub_time;
 wire[5:0]cache_ready;wire crc_alarm;wire[31:0]crc_alarm_frame,active_frame,active_crc,late_count;
 wire cache_filling,Sdr_busy;(* async_reg="true" *)reg[1:0]fill_sync,mbusy_sync,cache_valid_sync;
 wire ui_loading=loading||seek_busy||audio_rate_wait||photo_busy_sync[1]||(active_valid&&!cache_valid_sync[1]&&!browser);
 always @(posedge control_clk)if(rst_sys)begin fill_sync<=0;mbusy_sync<=0;cache_valid_sync<=0;end else begin fill_sync<={fill_sync[0],cache_filling};mbusy_sync<={mbusy_sync[0],Sdr_busy};cache_valid_sync<={cache_valid_sync[0],cache_frame_valid};end
 wire[15:0]target_frame;wire[31:0]media_pos_sys,media_ms_sys;wire[31:0]audio_uf_sys;
 wire auto_photo_tick;
 wire auto_next=auto_photo_tick&&photo_auto&&!adjust_mode&&!browser&&!((short_key|remote_short)&4'b0001);
 alpha_photo_slideshow slideshow_timer(control_clk,rst_sys,photo_auto,image_asset,browser,boot_done,
 ui_loading||adjust_mode,opened,next_photo||prev_photo||(|((short_key|remote_short)&4'b1100)),auto_photo_tick);
 alpha_media_control chooser(control_clk,rst_sys,pick,next_photo,prev_photo,auto_next,selected,next_video,prev_video,resource_count,valid_mask,image_mask,selected_ready,selected_type,
 q_lba,q_bytes,q_crc,q_audio_lba,q_audio_samples,q_duration,q_width,q_height,
 !store_busy&&!card_busy&&client_busy==0&&(!active_valid||(manager_idle&&!fill_sync[1]&&!mbusy_sync[1])),boot_done,manager_error,
 query_index,active_valid,image_asset,active_index,asset_lba,asset_bytes,asset_crc,audio_lba,audio_samples,duration_ms,asset_width,asset_height,loading,manager_enable,media_reset,audio_restart,opened);
 alpha_ui ui(.clk(control_clk),.rst(rst_sys),.short_press(short_key|remote_short),.long_press(long_key|remote_long),.repeat_press(repeat_key),.sw(sw),
 .catalog_ready(catalog_loaded),.resource_count(resource_count),.loading(ui_loading),.media_ready(boot_done),.image_mode(image_asset),.cue_done(cue_done),.selected_type(selected_type),.selected_ready(selected_ready),.image_mask(image_mask),.valid_mask(valid_mask),
 .selected(selected),.browser(browser),.fullscreen(fullscreen),.focus(focus),.display_view(display_view),.paused(paused),.muted(muted),.diagnostic(diagnostic),.scan(scan),.pick(pick),.next_photo(next_photo),.prev_photo(prev_photo),.next_video(next_video),.prev_video(prev_video),.step_next(step_next),.step_prev(step_prev),
 .cue_start(cue_start),.cue_index(cue_index),.cue_cancel(cue_cancel),.beep(beep),.beep_kind(beep_kind),.announcing(announcing),.photo_auto(photo_auto),.photo_period(photo_period),.opened(opened),.opened_index(active_index),.external_scan(remote_scan),
 .root_page(root_page),.folder_images(folder_images),.speed_mode(speed_mode),.analysis_on(analysis_on),.rate_q8_8(rate_q8_8),.repeat_mask(repeat_mask),.list_map(list_map),.list_count(list_count),.selected_row(selected_row),.adjust_mode(adjust_mode));
 alpha_frame_seek seeker(control_clk,rst_sys,browser||image_asset||loading||!active_valid,step_next,step_prev,active_frame[15:0],frame_count,nominal_fps,
 seek_ack,active_frame[15:0],cache_valid_sync[1],track_ready,pcm_flush,seek_busy,seek_toggle,seek_audio,seek_frame,seek_phase,seek_sample,seek_ms,seek_ms_phase);
 alpha_media_store #(.CLK_HZ(50000000)) store(.clk(control_clk),.rst(mrst_sys),.job_start(job_start),.job_kind(job_kind),.job_index(job_index),.job_slot(job_slot),.image_asset(image_asset),.asset_base(asset_lba),.asset_bytes(asset_bytes),.asset_crc(asset_crc),.photo_base(photo_destination),
 .job_done(job_done),.job_ok(job_ok),.error(store_error),.busy(store_busy),.debug_status(store_debug),.header_valid(header_valid),.frame_count(frame_count),.nominal_fps(nominal_fps),.default_threshold(default_threshold),.bmp_lba(bmp_lba),
 .crc_actual(job_crc),.crc_expected(job_expected),.timestamp_ms(job_timestamp),.card_initialized(card_init),.card_busy(client_busy[2]),.card_done(client_done[2]),.card_error(err_store),.card_start(request[2]),.card_lba(store_card_lba),.card_blocks(store_card_blocks),.card_data(card_data),.card_valid(client_valid[2]),.card_ready(client_ready[2]),
 .wr_req_toggle(wr_req_toggle),.wr_base(wr_base),.wr_len(wr_len),.wr_ack_toggle(wr_ack_toggle),.wr_done_toggle(wr_done_toggle),.wr_data(wr_data),.wr_valid(wr_valid),.wr_ready(wr_ready));
 wire frame_start,hs0,vs0,de0,timing_read_req;reg refresh_toggle;
 video_timing_data timing(video_clk,rst_video,timing_read_req,1'b1,frame_start,hs0,vs0,de0);
 always @(posedge video_clk)if(rst_video)refresh_toggle<=0;else if(frame_start)refresh_toggle<=~refresh_toggle;
 bb_replay_manager manager(.clk(control_clk),.rst(mrst_sys),.playing(!paused),.photo_mode(image_asset),.next_press(1'b0),.prev_press(1'b0),.enable(manager_enable&&!browser),.image_asset(image_asset),.target_frame(display_target_sys),.fast_mode(rate_q8_8>256),
 .rate_q8_8(16'd7680),.refresh_toggle(refresh_toggle),.pub_ack_toggle(pub_ack),.pub_req_toggle(pub_req),.pub_cur_base(pub_cur),.pub_hist_base(pub_hist),.pub_frame_id(pub_frame),.pub_timestamp_ms(pub_time),.pub_raw(pub_raw),.pub_valid(pub_valid),.pub_history(pub_history),.pub_crc(pub_crc),
 .job_start(job_start),.job_kind(job_kind),.job_index(job_index),.job_slot(job_slot),.job_done(job_done),.job_ok(job_ok),.job_error(store_error),.header_valid(header_valid),.frame_count(frame_count),.nominal_fps(nominal_fps),.job_crc(job_crc),.job_timestamp_ms(job_timestamp),
 .boot_done(boot_done),.error(manager_error),.cache_ready(cache_ready),.crc_alarm(crc_alarm),.crc_alarm_frame(crc_alarm_frame),.active_frame_id(active_frame),.active_crc(active_crc),.late_count(late_count),.idle(manager_idle));
 wire Sdr_init_done,Sdr_init_ref_vld,Sdr_rd_en,App_wr_en,App_rd_en;
 wire[20:0]App_wr_addr,App_rd_addr;wire[31:0]App_wr_din,Sdr_rd_dout;wire[3:0]App_wr_dm;
 wire rd_req_toggle,rd_ack_toggle,rd_done_toggle,history_enable,cur_pop,hist_pop;
 wire[20:0]cur_base,hist_base;wire[9:0]rd_words;wire[31:0]cur_data,hist_data;
 wire cur_valid,cur_empty,hist_valid,hist_empty,wr_overflow,mem_fault;
 bb_mem_ports mem_ports(.mem_clk(mem_clk),.src_clk(control_clk),.vid_clk(video_clk),.rst_mem(mrst_mem),.rst_src(mrst_sys),.rst_vid(mrst_video),
 .Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),.Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout),.App_wr_en(App_wr_en),.App_wr_addr(App_wr_addr),.App_wr_din(App_wr_din),.App_wr_dm(App_wr_dm),.App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),
 .wr_req_toggle(wr_req_toggle),.wr_base(wr_base),.wr_len(wr_len),.wr_ack_toggle(wr_ack_toggle),.wr_done_toggle(wr_done_toggle),.wr_data(wr_data),.wr_valid(wr_valid),.wr_ready(wr_ready),
 .rd_req_toggle(rd_req_toggle),.cur_base(cur_base),.hist_base(hist_base),.rd_words(rd_words),.history_enable(history_enable),.rd_ack_toggle(rd_ack_toggle),.rd_done_toggle(rd_done_toggle),.cur_pop(cur_pop),.hist_pop(hist_pop),.cur_data(cur_data),.cur_valid(cur_valid),.cur_empty(cur_empty),.hist_data(hist_data),.hist_valid(hist_valid),.hist_empty(hist_empty),.wr_overflow(wr_overflow),.mem_fault(mem_fault));
 sdram U3(.Clk(mem_clk),.Clk_sft(mem_clk_sft),.Rst(mrst_mem),.Sdr_init_done(Sdr_init_done),.Sdr_init_ref_vld(Sdr_init_ref_vld),.Sdr_busy(Sdr_busy),.App_wr_en(App_wr_en),.App_wr_addr(App_wr_addr),.App_wr_dm(App_wr_dm),.App_wr_din(App_wr_din),.App_rd_en(App_rd_en),.App_rd_addr(App_rd_addr),.Sdr_rd_en(Sdr_rd_en),.Sdr_rd_dout(Sdr_rd_dout));
 wire pcm_flush,fifo_we,fifo_full,cue_mode,track_ready;wire[15:0]fifo_din;wire[13:0]fifo_wcount,fifo_rcount;wire[31:0]track_samples;wire[3:0]audio_error;
 wire cue_finished_video;(* async_reg="true" *)reg[2:0]cue_finish_sync,loop_sync;wire loop_video;reg loop_toggle;
 always @(posedge video_clk)if(rst_video)loop_toggle<=0;else if(loop_video)loop_toggle<=~loop_toggle;
 reg loop_seen;always @(posedge control_clk)if(rst_sys)begin cue_finish_sync<=0;loop_sync<=0;loop_seen<=0;end else begin cue_finish_sync<={cue_finish_sync[1:0],cue_finished_video};loop_sync<={loop_sync[1:0],loop_toggle};loop_seen<=loop_sync[2];end
 alpha_audio_loader audio_loader(control_clk,rst_sys|media_reset,audio_restart||(loop_seen!=loop_sync[2]),cue_start,cue_cancel,cue_index,audio_lba,audio_samples,media_pos_sys,
 c0_lba,c1_lba,c2_lba,c3_lba,c0_samples,c1_samples,c2_samples,c3_samples,cue_finish_sync[2]&&!cue_finish_sync[1],
 client_busy[1]||!card_init,client_done[1],client_valid[1],card_data,err_audio,request[1],audio_card_lba,audio_card_blocks,client_ready[1],pcm_flush,fifo_we,fifo_din,fifo_full,fifo_wcount,cue_mode,track_ready,cue_done,track_samples,audio_error,seek_audio||rate_event,seek_audio ? seek_sample:media_pos_sys);
 (* async_reg="true" *)reg[1:0]flush_sync;
 always @(posedge video_clk)if(rst_video)flush_sync<=3;else flush_sync<={flush_sync[0],pcm_flush};
 wire fifo_pop,fifo_empty,fifo_rdvalid;wire[15:0]fifo_dout;
 alpha_pcm_fifo pcm_fifo(control_clk,rst_sys|pcm_flush,fifo_we,fifo_din,fifo_full,fifo_wcount,video_clk,rst_video|flush_sync[1],fifo_pop,fifo_dout,fifo_rdvalid,fifo_empty,fifo_rcount);
 (* async_reg="true" *)reg[1:0]memory_fault_sync;
 always @(posedge control_clk)if(rst_sys||media_reset)memory_fault_sync<=0;else memory_fault_sync<={memory_fault_sync[0],mem_fault};
 wire[3:0]app_error=catalog_error!=0?catalog_error:manager_error!=0?manager_error:audio_error!=0?audio_error:(memory_fault_sync[1]||wr_overflow)?4'he:4'd0;
 reg beep_toggle;always @(posedge control_clk)if(rst_sys)beep_toggle<=0;else if(beep||adjust_beep)beep_toggle<=~beep_toggle;
 wire[258:0]config_bus;wire config_update;
 bb_top_mailbox #(.WIDTH(259),.DEFAULT(259'd0)) settings(.src_clk(control_clk),.src_rst(rst_sys),.src_valid(1'b1),
 .src_data({adjust_mode,adjust_item,exposure,contrast,brightness,photo_auto,volume_percent,root_page,folder_images,speed_mode,rate_q8_8,list_map,list_count,selected_row,analysis_on,boot_done,browser,fullscreen,display_view,focus,paused,muted,diagnostic,announcing,ui_loading||catalog_busy,image_asset,resource_count,selected,valid_mask[11:0],image_mask[11:0],frame_count,nominal_fps[5:0],(browser?q_duration:duration_ms),(audio_samples!=0),(browser?q_width[10:0]:asset_width[10:0]),(browser?q_height[10:0]:asset_height[10:0]),app_error,cue_mode,track_ready,track_samples[19:0],beep_toggle,beep_kind}),.dst_clk(video_clk),.dst_rst(rst_video),.dst_apply(1'b1),.dst_valid(config_update),.dst_data(config_bus));
 wire vbboot,vbbrowser,vbfull,vpaused,vmuted,vdiag,vann,vloading,vbimage,vcuemode,vtrackready,vbeep_toggle;
 wire[1:0]vbview,vbfocus,vbeep_kind;wire[4:0]vcount;wire[3:0]vselected,verror;wire[15:0]vmask,vimages,vframes,vfps,vwidth,vheight;
 wire[11:0]vmask12,vimages12;wire[5:0]vfps6;wire[10:0]vwidth11,vheight11;wire[19:0]vtrack20;
 wire[31:0]vduration,vtrack_samples;wire vhas_audio;
 wire vadjust_mode;wire[1:0]vadjust_item;wire[7:0]vexposure,vcontrast,vbrightness;wire vphoto_auto;wire[7:0]vvolume;wire vbroot,vbfolder,vbspeed,vbanalysis;wire[10:0]vrate;wire[47:0]vbmap;wire[3:0]vblist,vbrow;
 assign {vadjust_mode,vadjust_item,vexposure,vcontrast,vbrightness,vphoto_auto,vvolume,vbroot,vbfolder,vbspeed,vrate,vbmap,vblist,vbrow,vbanalysis,vbboot,vbbrowser,vbfull,vbview,vbfocus,vpaused,vmuted,vdiag,vann,vloading,vbimage,vcount,vselected,vmask12,vimages12,vframes,vfps6,vduration,vhas_audio,vwidth11,vheight11,verror,vcuemode,vtrackready,vtrack20,vbeep_toggle,vbeep_kind}=config_bus;
 assign vmask={4'd0,vmask12};assign vimages={4'd0,vimages12};assign vfps={10'd0,vfps6};assign vwidth={5'd0,vwidth11};assign vheight={5'd0,vheight11};assign vtrack_samples={12'd0,vtrack20};
 reg vbrowser,vfull,vimage;reg[1:0]vview,vfocus;
 always @(posedge video_clk)if(rst_video)begin vbrowser<=1;vfull<=0;vview<=0;vfocus<=0;vimage<=0;end else if(frame_start)begin vbrowser<=vbbrowser;vfull<=vbfull||vbimage;vview<=vbimage?0:vbview;vfocus<=vbfocus;vimage<=vbimage;end
 reg vroot,vfolder,vspeed,vanalysis;reg[47:0]vmap;reg[3:0]vlist,vrow;
 always @(posedge video_clk)if(rst_video)begin vroot<=1;vfolder<=0;vspeed<=0;vanalysis<=0;vmap<=0;vlist<=0;vrow<=0;end
 else if(frame_start)begin vroot<=vbroot;vfolder<=vbfolder;vspeed<=vbspeed;vanalysis<=vbanalysis;vmap<=vbmap;vlist<=vblist;vrow<=vbrow;end
 wire[102:0]seek_bus;wire seek_update;reg seek_seen;
 bb_top_mailbox #(.WIDTH(103)) seek_command(control_clk,rst_sys,1'b1,{seek_toggle,seek_frame,seek_sample,seek_ms,seek_phase,seek_ms_phase},video_clk,rst_video,frame_start,seek_bus,seek_update);
 wire seek_now=seek_update&&seek_bus[102]!=seek_seen;
 always @(posedge video_clk)if(rst_video)seek_seen<=0;else if(seek_now)seek_seen<=seek_bus[102];
 wire[31:0]elapsed_samples,elapsed_sys;wire sample_ce,media_advance;wire clock_advance=vrate==256 ? media_advance:!vpaused&&vbboot&&!vloading&&cache_frame_valid&&!vcuemode;wire[31:0]media_samples,media_ms;wire[15:0]media_frame;wire[7:0]media_fraction;
 alpha_clock clock(video_clk,rst_video,mrst_video,clock_advance,vbimage?16'd1:vfps,vbimage?16'hffff:vframes,sample_ce,media_samples,media_ms,media_frame,media_fraction,loop_video,vrate,seek_now,seek_bus[85:54],seek_bus[53:22],seek_bus[101:86],seek_bus[21:6],seek_bus[5:0],elapsed_samples);
 reg[1:0]fast_div;reg[15:0]fast_frame;wire[15:0]display_target_sys;
 always @(posedge video_clk)if(rst_video||mrst_video)begin fast_div<=0;fast_frame<=0;end
 else if(frame_start)begin fast_div<=fast_div==2 ? 0:fast_div+1'b1;if(fast_div==0||vpaused)fast_frame<=media_frame;end
 wire[15:0]display_target_video=vrate>256 ? fast_frame:media_frame;
 wire[160:0]back_bus;wire back_updated;
 wire[31:0]audio_underflows;
 bb_top_mailbox #(.WIDTH(161),.DEFAULT(161'd0)) timeline(.src_clk(video_clk),.src_rst(rst_video),.src_valid(1'b1),.src_data({elapsed_samples,seek_seen,display_target_video,audio_underflows,media_samples,media_ms,media_frame}),.dst_clk(control_clk),.dst_rst(rst_sys),.dst_apply(1'b1),.dst_valid(back_updated),.dst_data(back_bus));
 assign {elapsed_sys,seek_ack,display_target_sys,audio_uf_sys,media_pos_sys,media_ms_sys,target_frame}=back_bus;
 reg beep_seen;wire video_beep=vbeep_toggle!=beep_seen;always @(posedge video_clk)if(rst_video)beep_seen<=0;else beep_seen<=vbeep_toggle;
 wire[23:0]pcm;wire media_pcm_valid;wire signed[15:0]media_pcm_sample;wire audio_valid;
 alpha_audio_out audio_out(video_clk,rst_video,flush_sync[1],sample_ce,vpaused||vrate!=256,vmuted,vbboot&&!vloading&&cache_frame_valid&&(vbimage||media_frame<=cache_frame[15:0]+16'd1||media_frame==0),vhas_audio,vcuemode,vtrackready,vtrack_samples,
 fifo_empty,fifo_rdvalid,fifo_dout,fifo_pop,video_beep,vbeep_kind,cue_finished_video,media_advance,audio_valid,pcm,media_pcm_valid,media_pcm_sample,audio_underflows);
 wire[7:0]spectrum_bar_value;wire[7:0]spectrum_bar_query;wire[7:0]peak_bin;wire[15:0]peak_level;wire wave_complete;
 // User selected a time waveform+energy;FFT source retained but not instantiated.
 assign spectrum_bar_value=0;assign peak_bin=0;assign peak_level=0;
 wire[7:0]wave_query;wire signed[15:0]wave_min,wave_max;wire wave_valid;wire[7:0]wave_energy;wire[8:0]wave_bins;
 alpha_waveform waveform(video_clk,rst_video||mrst_video||seek_now||flush_sync[1],vhas_audio&&!vcuemode&&vtrackready&&vrate==256&&!vbrowser,frame_start,media_pcm_valid,media_pcm_sample,wave_query,wave_min,wave_max,wave_valid,wave_energy,wave_bins,wave_complete);
 wire cache_accepted;wire chs,cvs,cde,primary,cache_history_valid,cache_raw,cache_crc,cache_underflow,underflow_event;
 wire[23:0]current_rgb,future_rgb;wire[9:0]sx,sourcex;wire[8:0]sy,sourcey;wire[31:0]cache_frame,cache_time;
 bb_video_cache cache(.clk(video_clk),.rst(mrst_video),.frame_start(frame_start),.hs(hs0),.vs(vs0),.de(de0),.quad_mode(!vfull&&!vimage),
 .pub_req_toggle(pub_req),.pub_cur_base(image_asset?photo_destination:pub_cur),.pub_hist_base(image_asset?photo_previous:pub_hist),.pub_frame_id(pub_frame),.pub_timestamp_ms(pub_time),.pub_raw(pub_raw),.pub_valid(pub_valid),.pub_history(image_asset?photo_previous_valid:pub_history),.pub_crc(pub_crc),.pub_ack_toggle(pub_ack),.pub_accepted(cache_accepted),
 .frame_id(cache_frame),.timestamp_ms(cache_time),.raw_mode(cache_raw),.frame_valid(cache_frame_valid),.history_valid(cache_history_valid),.crc_ok(cache_crc),
 .rd_req_toggle(rd_req_toggle),.cur_base(cur_base),.hist_base(hist_base),.rd_words(rd_words),.history_enable(history_enable),.rd_done_toggle(rd_done_toggle),
 .cur_pop(cur_pop),.hist_pop(hist_pop),.cur_data(cur_data),.hist_data(hist_data),.cur_valid(cur_valid),.cur_empty(cur_empty),.hist_valid(hist_valid),.hist_empty(hist_empty),
 .ohs(chs),.ovs(cvs),.ode(cde),.rgb(current_rgb),.prev_rgb(future_rgb),.screenx(sx),.screeny(sy),.sourcex(sourcex),.sourcey(sourcey),.primary(primary),.underflow(cache_underflow),.underflow_event(underflow_event),.filling_busy(cache_filling),.hold_photo(photo_previous_valid&&image_asset),.hold_base(photo_previous));
 // Publish after cache metadata has committed, before the first pixel
 // reaches the renderer; the early VSYNC edge still sees the old cache ID.
 reg motion_publish,wait_first_active;
 always @(posedge video_clk)begin
  if(rst_video)begin motion_publish<=0;wait_first_active<=0;end
  else begin motion_publish<=0;if(frame_start)wait_first_active<=1;
   if(wait_first_active&&de0)begin motion_publish<=1;wait_first_active<=0;end
  end
 end
 wire motion_frame_valid,motion_history_flag;
 wire[3:0]motion_valid;wire[111:0]motion_boxes;wire[31:0]motion_id,motion_time,energy,summary_id,motion_skipped;wire[18:0]motion_count;wire[1:0]scene;wire summary,event_pulse,motion_busy;
 bb3_motion_engine motion(video_clk,mrst_video,motion_publish,cache_frame,cache_time,cache_frame-1'b1,cache_frame_valid&&vbanalysis&&!vimage&&!vbrowser,cache_history_valid,cache_raw,
 !vfull&&!vimage,cde,sx,sy,current_rgb,future_rgb,8'd18,1'b0,1'b0,9'd0,8'd0,,motion_history_flag,motion_frame_valid,motion_id,motion_time,motion_valid,motion_boxes,scene,energy,motion_count,summary,summary_id,event_pulse,motion_skipped,motion_busy);
 wire motion_matches_current=motion_frame_valid&&motion_id==cache_frame;
 wire motion_matches_history=motion_frame_valid&&cache_history_valid&&cache_frame!=0&&motion_id==cache_frame-1'b1;
 wire motion_use_previous=!motion_matches_current&&motion_matches_history;
 wire[3:0]matched_boxes=(motion_matches_current||motion_matches_history)?motion_valid:4'd0;
 wire[3:0]box_count={3'd0,matched_boxes[0]}+{3'd0,matched_boxes[1]}+{3'd0,matched_boxes[2]}+{3'd0,matched_boxes[3]};
 wire[7:0]interpolation_phase=vrate>256 ? 8'd0:!cache_history_valid?8'd0:media_frame==cache_frame[15:0]?media_fraction:media_frame>cache_frame[15:0]?8'd255:8'd0;
 wire ohs,ovs,ode;wire[23:0]out_rgb;wire[31:0]video_time_bcd;
 wire uhs,uvs,ude;wire[9:0]ux;wire[8:0]uy;
 alpha_video_cursor cursor(video_clk,rst_video,frame_start,hs0,vs0,de0,uhs,uvs,ude,ux,uy);
 wire[23:0]photo_display_rgb;
 wire motion_pane=!vbrowser&&!vimage&&(vfull ? vview==2:(ux<320&&uy>=240));
 wire[23:0]view_source_rgb=motion_pane&&motion_use_previous?future_rgb:current_rgb;
 wire motion_header=vfull&&vview==2&&(motion_matches_current||motion_matches_history);
 alpha_photo_transition photo_transition(video_clk,rst_video,frame_start,cache_accepted,vimage,cache_history_valid,vbrowser,photo_backwards,ux,uy,current_rgb,future_rgb,photo_display_rgb,photo_busy_video);
 alpha_views views(video_clk,rst_video,frame_start,uhs,uvs,ude,ux,uy,vimage?photo_display_rgb:view_source_rgb,future_rgb,interpolation_phase,vfull,vview,vfocus,
 vbrowser,vloading&&!(vimage&&photo_previous_valid),vpaused,vmuted,vhas_audio,vdiag,vann,vimage,verror,vselected,vcount,vmask,vimages,name_item,name_char,name_data,motion_header?motion_time:media_ms,vduration,motion_header?motion_id[15:0]:cache_frame[15:0],vwidth,vheight,matched_boxes,motion_boxes,spectrum_bar_value,peak_bin,peak_level,audio_underflows,spectrum_bar_query,ohs,ovs,ode,out_rgb,video_time_bcd,vroot,vfolder,vspeed,vanalysis,vrate,vmap,vlist,vrow,wave_min,wave_max,wave_valid,wave_query,cache_history_valid&&vbanalysis,vphoto_auto,vadjust_mode,vadjust_item,vexposure,vcontrast,vbrightness,vvolume,wave_energy,wave_bins,motion_id[15:0]);
 wire[69:0]board_bus;wire board_updated;wire[31:0]board_ms;wire board_full;wire[1:0]board_view;wire[3:0]board_boxes;
 bb_top_mailbox #(.WIDTH(39),.DEFAULT(39'd0)) board_snapshot(.src_clk(video_clk),.src_rst(rst_video),.src_valid(1'b1),.src_data({video_time_bcd,vfull,vview,box_count}),.dst_clk(clk),.dst_rst(rst50),.dst_apply(1'b1),.dst_valid(board_updated),.dst_data(board_bus[38:0]));
 assign {board_ms,board_full,board_view,board_boxes}=board_bus[38:0];
 alpha_seg digits(clk,rst50,board_ms,board_full,board_view,board_boxes,seg_sel,seg_data);
 wire[7:0]rx_data,tx_data;wire rx_valid,tx_valid,tx_ready;
 bb_uart8n1 #(.CLK_HZ(50000000)) uart(control_clk,rst_sys,uart_rx,rx_data,rx_valid,tx_data,tx_valid,tx_ready,uart_tx);
 wire[7:0]control_seq,control_cmd,control_status;wire[7:0]volume_percent;
 alpha_remote_keys #(.TIMEOUT_CYCLES(8388608)) remote(control_clk,rst_sys,rx_data,rx_valid,(ui_loading||catalog_busy||!catalog_loaded)&&!adjust_mode,
 remote_short,remote_long,remote_scan,control_seq,control_cmd,control_status,volume_percent,local_volume_set,local_volume);
 (* async_reg="true" *)reg[3:0]key_meta,key_levels;reg[3:0]last_short,last_long;reg[7:0]short_count,long_count;
 (* async_reg="true" *)reg[2:0]commit_sync;reg commit_seen;reg[31:0]frame_commits;
 always @(posedge control_clk)begin
  if(rst_sys)begin key_meta<=15;key_levels<=15;last_short<=0;last_long<=0;short_count<=0;long_count<=0;
   commit_sync<=0;commit_seen<=0;frame_commits<=0;
  end else begin
   key_meta<={key2,key3,key1,rst_n};key_levels<=key_meta;
   if(short_key!=0)begin last_short<=short_key;short_count<=short_count+1'b1;end
   if(long_key!=0)begin last_long<=long_key;long_count<=long_count+1'b1;end
   commit_sync<={commit_sync[1:0],pub_ack};commit_seen<=commit_sync[2];
   if(commit_seen!=commit_sync[2])frame_commits<=frame_commits+1'b1;
  end
 end
 reg[31:0]live_pcm_count,wave_complete_count;
 always @(posedge video_clk)begin
  if(mrst_video)begin live_pcm_count<=0;wave_complete_count<=0;end
  else begin if(media_pcm_valid)live_pcm_count<=live_pcm_count+1'b1;if(wave_complete)wave_complete_count<=wave_complete_count+1'b1;end
 end
 wire[191:0]analysis_debug;wire analysis_debug_updated;
 bb_top_mailbox #(.WIDTH(192)) analysis_snapshot(video_clk,rst_video,1'b1,
 {30'd0,motion_frame_valid,motion_use_previous,{23'd0,wave_bins},wave_complete_count,live_pcm_count,motion_id[15:0],cache_frame[15:0],32'h39545241},
 control_clk,rst_sys,1'b1,analysis_debug,analysis_debug_updated);
 alpha_status_tx #(.CLK_HZ(50000000)) status_tx(control_clk,rst_sys,{catalog_loaded,fullscreen,image_asset,boot_done&&!crc_alarm,!paused,announcing,ui_loading,browser},{4'd0,app_error},{3'd0,resource_count},{4'd0,selected},active_frame[15:0],nominal_fps,media_ms_sys,media_pos_sys,audio_uf_sys,
 valid_mask,image_mask,{catalog_busy,selected_ready,selected_type,key_levels},{root_page,folder_images,analysis_on,manager_idle,header_valid,cache_valid_sync[1],boot_done,active_valid},
 {last_long,last_short},short_count,long_count,control_seq,control_cmd,control_status,q_lba,q_bytes,frame_commits,{5'd0,rate_q8_8},{3'd0,seek_busy,speed_mode,analysis_on,folder_images,root_page},{selected_row,list_count},elapsed_sys,tx_data,tx_valid,tx_ready,{{5'd0,adjust_item,adjust_mode},brightness,contrast,exposure,{3'd0,display_view,focus,fullscreen},7'd0,photo_auto,6'd0,analysis_debug[161:160],volume_percent,analysis_debug[159:0]});
 assign led={app_error!=0,track_ready,!paused,catalog_loaded};
 wire acr_valid;wire[19:0]acr_cts,acr_n;wire audio_hdmi_valid;wire[23:0]pcm_hdmi;
 alpha_volume master_volume(video_clk,rst_video,audio_valid,pcm,vvolume,audio_hdmi_valid,pcm_hdmi);
 wire[23:0]pcm_left=pcm_hdmi,pcm_right=pcm_hdmi;
 audio_arc_calculate #(.ACR_N(6144)) acr(.I_clk(video_clk),.I_rst(rst_video),.I_audio_valid(audio_hdmi_valid),
  .O_acr_valid(acr_valid),.O_acr_cts(acr_cts),.O_acr_n(acr_n));
 wire axis_user,axis_valid,axis_last,axis_ready;wire [23:0] axis_data;
 video_rgb_to_axis_640x480 axis(.I_clk(video_clk),.I_rst(rst_video),.I_vs(ovs),.I_de(ode),.I_rgb(out_rgb),
  .O_video_user(axis_user),.O_video_valid(axis_valid),.O_video_last(axis_last),.O_video_data(axis_data));
 wire edid_trig,edid_valid;wire [7:0] edid_data;wire [9:0] tmds0,tmds1,tmds2,tmdsclk;
 startup_pulse #(.CNT_MAX(20'd100000)) startup(.I_clk(video_clk),.I_rst(rst_video),.O_pulse(edid_trig));
 hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
  .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),.VIDEO_VIC(1),.VIDEO_TPG("Disable"),
  .VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)) hdmi(
  .I_pixel_clk(video_clk),.I_rst(rst_video),.I_edid_read_trig(edid_trig),.O_edid_read_valid(edid_valid),.O_edid_read_data(edid_data),
  .I_axis_s_user(axis_user),.I_axis_s_valid(axis_valid),.I_axis_s_last(axis_last),.I_axis_s_data(axis_data),.O_axis_s_ready(axis_ready),
  .I_audio_valid(audio_hdmi_valid),.I_audio_left_data(pcm_left),.I_audio_right_data(pcm_right),.I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),
  .O_video_locked(),.O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
  .O_ch0_tmds_data(tmds0),.O_ch1_tmds_data(tmds1),.O_ch2_tmds_data(tmds2),.O_clk_tmds_data(tmdsclk));
 hdmi_phy_wrapper #(.DEVICE("EG")) phy(.I_pixel_clk(video_clk),.I_serial_clk(serial_clk),.I_rst(rst_video),
  .I_tmds_channel_0(tmds0),.I_tmds_channel_1(tmds1),.I_tmds_channel_2(tmds2),.I_tmds_channel_clk(tmdsclk),
  .O_tmds_ch0_p(HDMI_D0_P),.O_tmds_ch1_p(HDMI_D1_P),.O_tmds_ch2_p(HDMI_D2_P),.O_tmds_clk_p(HDMI_CLK_P));
endmodule
