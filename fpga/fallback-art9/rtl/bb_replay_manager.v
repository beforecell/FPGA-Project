// A fully associative compressed-frame reservoir. Publication and loading are
// independent: a slow card read cannot block publication of a verified frame.
module bb_replay_manager(
 input clk,rst,playing,photo_mode,next_press,prev_press,input enable,image_asset,input[15:0]target_frame,
 input [15:0] rate_q8_8,input refresh_toggle,input pub_ack_toggle,
 output reg pub_req_toggle,output reg [20:0] pub_cur_base,pub_hist_base,
 output reg [31:0] pub_frame_id,pub_timestamp_ms,
 output reg pub_raw,pub_valid,pub_history,pub_crc,
 output reg job_start,output reg [1:0] job_kind,output reg [15:0] job_index,
 output reg [4:0] job_slot,
 input job_done,job_ok,input [3:0] job_error,input header_valid,
 input [15:0] frame_count,nominal_fps,input [31:0] job_crc,job_timestamp_ms,
 output reg boot_done,output reg [3:0] error,output reg [5:0] cache_ready,
 output reg crc_alarm,output reg [31:0] crc_alarm_frame,
 output reg [31:0] active_frame_id,active_crc,late_count,output idle,input fast_mode
);
 // Two synchronous directory copies permit simultaneous display and loader
 // lookup. Each entry is {CRC32,timestamp_ms,frame_id16}; payload validity is
 // reset separately, so block RAM data needs no expensive reset mux tree.
 reg [31:0] valid;
 reg invalidate_pending;reg[4:0]invalidate_slot;
 reg [15:0] wanted;reg [1:0] wanted_photo;reg last_photo;
 reg [15:0] phase;reg [18:0] photo_phase;
 reg [31:0] photo_crc[0:3];
 (* async_reg="true" *)reg [2:0] refresh_sync,ack_sync;
 reg refresh_seen,publishing,active_valid,active_raw;
 reg [4:0] active_cur_slot,active_hist_slot,pending_cur_slot,pending_hist_slot;
 wire pub_ack=publishing && ack_sync[2]==pub_req_toggle;
 wire tick=refresh_sync[2]!=refresh_seen;
 wire [16:0] phase_sum={1'b0,phase}+{1'b0,rate_q8_8};
 // Shared rate control:30FPS ->60VS/photo,60FPS ->30VS/photo,
 // 1FPS ->1800VS/photo. Each photo lasts30 nominal video-frame periods.
 wire [19:0] photo_phase_sum={1'b0,photo_phase}+{4'd0,rate_q8_8};
 // Header count is stable before boot_done. Register its last valid index so
 // wrap comparison runs in parallel with increment, instead of after carry.
 reg [15:0] last_frame,wanted_inc,ahead_next;reg wanted_wrap;
 function [15:0] previous;input [15:0] n;begin previous=n==0 ? 16'd0:n-16'd1;end endfunction
 function [15:0] following;input [15:0] n;begin following=n==last_frame ? 16'd0:n+16'd1;end endfunction
 function [20:0] slot_base;input [4:0] n;begin slot_base=21'd614400+n*21'd57600;end endfunction
 reg [15:0] wanted_prev;wire [15:0] wanted_next=wanted_wrap ? 16'd0:wanted_inc;
 wire display_matches=active_valid && active_raw==photo_mode &&
    (photo_mode?active_frame_id[1:0]==wanted_photo:active_frame_id[15:0]==wanted);
 wire acknowledged_matches=pub_ack && pub_raw==photo_mode &&
    (photo_mode?pub_frame_id[1:0]==wanted_photo:pub_frame_id[15:0]==wanted);

 // Register the directory read before comparing it. Keeping the 32:1 mux
 // and target comparison in separate cycles closes the 100MHz control path.
 reg [5:0] pscan;reg [15:0] ptarget,pprevious;reg pcur_found,phist_found;
 reg [4:0] pcur,phist;
 reg [1:0] pread;reg pcur_match,phist_match;
 wire [79:0] pentry,lentry;wire [15:0] ptag=pentry[15:0];reg pvalid;
 reg [31:0] selected_time,selected_crc,pending_crc;
 // Loader: global header, four BMPs, then current/history and 16 frames ahead.
 localparam BOOT_START=0,BOOT_WAIT=1,PHOTO_START=2,PHOTO_WAIT=3,
            PICK=4,FIND=5,VICTIM=6,LOAD_WAIT=7,HALT=8,
            FIND_COMPARE=9,VICTIM_CHECK=10,VICTIM_DECIDE=11;
 assign idle=(state==PICK||state==HALT)&&!publishing;
 reg [3:0] state;reg [1:0] photo_load;reg [4:0] ahead,victim_next;
 reg [15:0] candidate,ahead_frame;reg [5:0] scan;
 reg [4:0] victim;reg [15:0] loading_id;
 wire [15:0] ltag=lentry[15:0];reg lvalid;
 reg victim_protected;reg [15:0] victim_epoch;
 wire protected_slot=(active_valid&&!active_raw &&
       (scan[4:0]==active_cur_slot || scan[4:0]==active_hist_slot)) ||
       (publishing&&!pub_raw &&
       (scan[4:0]==pending_cur_slot || scan[4:0]==pending_hist_slot)) ||
       (lvalid && (ltag==wanted || ltag==wanted_prev || ltag==wanted_next));
 wire directory_write=state==LOAD_WAIT && job_done && job_ok;
 wire [79:0] directory_data={job_crc,job_timestamp_ms,loading_id};
 bb_directory_ram directory_display(clk,directory_write,victim,directory_data,pscan[4:0],pentry);
 bb_directory_ram directory_loader(clk,directory_write,victim,directory_data,scan[4:0],lentry);
 integer i;
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   valid<=0;invalidate_pending<=0;invalidate_slot<=0;wanted_prev<=0;wanted<=0;last_frame<=0;wanted_inc<=1;wanted_wrap<=0;ahead_next<=1;wanted_photo<=0;last_photo<=0;phase<=0;photo_phase<=0;
   refresh_sync<=0;ack_sync<=0;refresh_seen<=0;publishing<=0;
   active_valid<=0;active_raw<=0;active_cur_slot<=0;active_hist_slot<=0;
   pending_cur_slot<=0;pending_hist_slot<=0;
   pub_req_toggle<=0;pub_cur_base<=0;pub_hist_base<=0;pub_frame_id<=0;
   pub_timestamp_ms<=0;pub_raw<=0;pub_valid<=0;pub_history<=0;pub_crc<=0;
   job_start<=0;job_kind<=0;job_index<=0;job_slot<=0;boot_done<=0;
   error<=0;cache_ready<=0;crc_alarm<=0;crc_alarm_frame<=0;
   active_frame_id<=0;active_crc<=0;late_count<=0;
   pscan<=0;ptarget<=0;pprevious<=0;pcur_found<=0;phist_found<=0;pcur<=0;phist<=0;
   pread<=0;pvalid<=0;pcur_match<=0;phist_match<=0;lvalid<=0;victim_protected<=1;victim_epoch<=0;
   selected_time<=0;selected_crc<=0;pending_crc<=0;
   state<=BOOT_START;photo_load<=0;ahead<=0;ahead_frame<=0;candidate<=0;
   scan<=0;victim<=0;victim_next<=0;loading_id<=0;
   for(i=0;i<4;i=i+1)photo_crc[i]<=0;
  end else begin
   refresh_sync<={refresh_sync[1:0],refresh_toggle};
   last_frame<=frame_count==0 ? 16'd0:frame_count-16'd1;
   ack_sync<={ack_sync[1:0],pub_ack_toggle};
   job_start<=0;crc_alarm<=0;last_photo<=photo_mode;
   // Separate target-epoch/protection decisions from the 24-entry valid bank.
   // The consumer observes job_start on this same following edge, so the slot
   // is invalidated before any load can write data. LOAD_WAIT success below
   // deliberately has priority if a zero-latency model completes immediately.
   invalidate_pending<=0;
   if(invalidate_pending)valid[invalidate_slot]<=0;
   // Scratch tag has no validity on its own. Capture outside the scan restart
   // priority tree; phist_found is still cleared/rechecked against ptarget.
   if(pread==2&&phist_match)phist<=pscan[4:0];
   // Lookup already has request/read/compare stages. Register the target's
   // predecessor before compare, removing subtract+compare from the100MHz path.
   pprevious<=previous(ptarget);wanted_prev<=previous(wanted);
   // ahead_frame is unchanged throughout the directory search. Compute its
   // successor there, before the next PICK state's candidate selection mux.
   ahead_next<=following(ahead_frame);
   if(tick)refresh_seen<=refresh_sync[2];
   if(pub_ack)begin
    publishing<=0;active_valid<=pub_valid;active_raw<=pub_raw;
    active_frame_id<=pub_frame_id;active_cur_slot<=pending_cur_slot;
    active_hist_slot<=pending_hist_slot;
    active_crc<=pub_raw?photo_crc[pub_frame_id[1:0]]:pending_crc;
   end

   if(boot_done&&error==0)begin
    if(photo_mode)wanted_photo<=0;
    else if(target_frame<frame_count)begin
     wanted<=target_frame;wanted_inc<=target_frame+16'd1;wanted_wrap<=target_frame==last_frame;
    end
   end

   if(!boot_done || publishing || display_matches || error!=0 || photo_mode!=last_photo)begin
    pscan<=0;ptarget<=wanted;pcur_found<=0;phist_found<=0;pread<=0;
   end else if(photo_mode)begin
    pub_cur_base<=wanted_photo*21'd153600;pub_hist_base<=0;
    pub_frame_id<={30'h20000000,wanted_photo};pub_timestamp_ms<=0;
    pub_raw<=1;pub_valid<=1;pub_history<=0;pub_crc<=1;
    pub_req_toggle<=~pub_req_toggle;publishing<=1;
   end else if(ptarget!=wanted)begin
    pscan<=0;ptarget<=wanted;pcur_found<=0;phist_found<=0;pread<=0;
   end else if(pscan<24)begin
    if(pread==0)begin pvalid<=valid[pscan[4:0]];pread<=1;end
    else if(pread==1)begin
     // Split BRAM tag comparison from the high-fanout metadata clock enable.
     // pscan stays fixed until the matched timestamp and CRC are captured.
     pcur_match<=pvalid&&ptag==ptarget;phist_match<=pvalid&&ptag==pprevious;pread<=2;
    end
    else begin
     if(pcur_match)begin
      pcur_found<=1;pcur<=pscan[4:0];selected_time<=pentry[47:16];selected_crc<=pentry[79:48];
     end
     if(phist_match)phist_found<=1;
     pscan<=pscan+1'b1;pread<=0;
    end
   end else if(pcur_found&&phist_found)begin
    pub_cur_base<=slot_base(pcur);pub_hist_base<=slot_base(phist);
    pub_frame_id<={16'd0,ptarget};pub_timestamp_ms<=selected_time;pending_crc<=selected_crc;
    pending_cur_slot<=pcur;pending_hist_slot<=phist;
    pub_raw<=0;pub_valid<=1;pub_history<=frame_count>1&&ptarget!=0;pub_crc<=1;
    pub_req_toggle<=~pub_req_toggle;publishing<=1;pscan<=0;
   end else begin pscan<=0;pcur_found<=0;phist_found<=0;end

   case(state)
    BOOT_START:begin job_kind<=0;job_index<=0;job_slot<=0;job_start<=1;state<=BOOT_WAIT;end
    BOOT_WAIT:if(job_done)begin
     if(job_ok&&header_valid)begin if(image_asset)begin photo_load<=0;state<=PHOTO_START;end else begin boot_done<=1;state<=PICK;end end
     else begin error<=job_error==0?4'h1:job_error;state<=HALT;end
    end
    PHOTO_START:begin job_kind<=1;job_index<={14'd0,photo_load};job_start<=1;state<=PHOTO_WAIT;end
    PHOTO_WAIT:if(job_done)begin
     if(!job_ok)begin error<=job_error;state<=HALT;end
     else begin
      photo_crc[photo_load]<=job_crc;
      if(photo_load==0)begin boot_done<=1;state<=PICK;ahead<=0;end
      else begin photo_load<=photo_load+1'b1;state<=PHOTO_START;end
     end
    end
    // A catalog image is one BMP asset. Its PHOTO_START/WAIT job has already
    // loaded it; issuing video-frame prefetch here would never complete.
    PICK:if(enable&&!image_asset)begin
     if(ahead==0)begin candidate<=wanted;ahead_frame<=wanted;end
     else if(ahead==1)candidate<=wanted_prev;
     else begin candidate<=ahead_next;ahead_frame<=ahead_next;end
     scan<=0;state<=FIND;
    end
    FIND:begin
     if(scan==24)begin scan<={1'b0,victim_next};victim<=victim_next;state<=VICTIM;end
     else begin lvalid<=valid[scan[4:0]];state<=FIND_COMPARE;end
    end
    FIND_COMPARE:begin
     if(lvalid&&ltag==candidate)begin
      ahead<=ahead>=(fast_mode ? 1:17) ? 0:ahead+1'b1;state<=PICK;
     end else begin scan<=scan+1'b1;state<=FIND;end
    end
    VICTIM:begin
     lvalid<=valid[scan[4:0]];state<=VICTIM_CHECK;
    end
    VICTIM_CHECK:begin
     victim_protected<=protected_slot;victim_epoch<=wanted;state<=VICTIM_DECIDE;
    end
    VICTIM_DECIDE:begin
     // A user step or a playback tick can change the requested frame during
     // this pipeline. Recheck rather than consuming a stale protection result.
     if(victim_epoch!=wanted)state<=VICTIM_CHECK;
     else if(!victim_protected)begin
      job_kind<=2;job_index<=candidate;job_slot<=scan[4:0];job_start<=1;
      loading_id<=candidate;victim<=scan[4:0];victim_next<=scan[4:0]==23?0:scan[4:0]+1'b1;
      if(lvalid)cache_ready<=cache_ready-1'b1;
      invalidate_slot<=scan[4:0];invalidate_pending<=1;state<=LOAD_WAIT;
     end else begin scan<=scan[4:0]==23?0:{1'b0,scan[4:0]+5'd1};state<=VICTIM;end
    end
    LOAD_WAIT:if(job_done)begin
     if(job_ok)begin
      valid[victim]<=1;cache_ready<=cache_ready+1'b1;
      // Always prioritize the current request again after a long card transfer.
      ahead<=0;state<=PICK;
     end else begin
      error<=job_error==0?4'h9:job_error;crc_alarm<=1;crc_alarm_frame<={16'd0,loading_id};state<=HALT;
     end
    end
    HALT:;
    default:state<=BOOT_START;
   endcase
  end
 end
endmodule

module bb_directory_ram(input clk,we,input [4:0] wa,input [79:0] din,
                        input [4:0] ra,output [79:0] dout);
`ifdef __ICARUS__
 reg [79:0] mem[0:31];reg [79:0] q;
 always @(posedge clk)begin if(we)mem[wa]<=din;q<=mem[ra];end
 assign dout=q;
`else
 wire [95:0] padded={16'd0,din};wire [95:0] q;
 genvar n;
 generate for(n=0;n<3;n=n+1)begin:bank
  EG_LOGIC_BRAM #(.DATA_WIDTH_A(32),.DATA_WIDTH_B(32),.ADDR_WIDTH_A(5),.ADDR_WIDTH_B(5),
   .DATA_DEPTH_A(32),.DATA_DEPTH_B(32),.BYTE_ENABLE(0),.MODE("DP"),
   .REGMODE_A("NOREG"),.REGMODE_B("NOREG"),.WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
   .RESETMODE("SYNC"),.IMPLEMENT("9K")) storage(
   .clka(clk),.cea(1'b1),.wea(we),.rsta(1'b0),.ocea(1'b0),.dia(padded[n*32+:32]),.addra(wa),.bea(1'b1),.doa(),
   .clkb(clk),.ceb(1'b1),.web(1'b0),.rstb(1'b0),.oceb(1'b1),.dib(32'd0),.addrb(ra),.beb(1'b1),.dob(q[n*32+:32]));
 end endgenerate
 assign dout=q[79:0];
`endif
endmodule
