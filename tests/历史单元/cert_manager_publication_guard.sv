module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,refresh=0,ack=0;reg[15:0]target=0;
wire req,raw,pvalid,hist,pcrc,start,boot,alarm,idle;wire[20:0]cur,prev;
wire[31:0]pid,ptime,alarmid,active,activecrc,late;wire[1:0]kind;wire[15:0]idx;wire[4:0]slot;
wire[3:0]err;wire[5:0]ready;reg done=0;reg[31:0]crc=0,stamp=0;
reg[15:0]frames=50;integer wait_job=0,ack_delay=0,clock_n=0,commits=0;
reg[15:0]tags[0:23];reg[23:0]known=0;reg[1:0]load_kind;reg[4:0]load_slot;reg[15:0]load_id;
bb_replay_manager dut(.clk(clk),.rst(rst),.playing(1'b1),.photo_mode(1'b0),.next_press(1'b0),.prev_press(1'b0),
 .fast_mode(1'b0),.enable(1'b1),.image_asset(1'b0),.target_frame(target),.rate_q8_8(16'd7680),.refresh_toggle(refresh),.pub_ack_toggle(ack),
 .pub_req_toggle(req),.pub_cur_base(cur),.pub_hist_base(prev),.pub_frame_id(pid),.pub_timestamp_ms(ptime),
 .pub_raw(raw),.pub_valid(pvalid),.pub_history(hist),.pub_crc(pcrc),.job_start(start),.job_kind(kind),.job_index(idx),.job_slot(slot),
 .job_done(done),.job_ok(1'b1),.job_error(4'd0),.header_valid(1'b1),.frame_count(frames),.nominal_fps(16'd25),.job_crc(crc),.job_timestamp_ms(stamp),
 .boot_done(boot),.error(err),.cache_ready(ready),.crc_alarm(alarm),.crc_alarm_frame(alarmid),.active_frame_id(active),.active_crc(activecrc),.late_count(late),.idle(idle));
always @(negedge clk)if(!rst)begin
 clock_n=clock_n+1;if(clock_n%100==0)refresh=~refresh;
 done=0;
 if(start)begin if(wait_job)$fatal(1,"overlapping jobs");wait_job=10;crc=idx+32'h12340000;stamp=idx*40;
 load_kind=kind;load_slot=slot;load_id=idx;
 if(kind==2&&(idx>=frames||slot>=24))$fatal(1,"bad job address");
 if(kind==2&&dut.active_valid&&(slot==dut.active_cur_slot||slot==dut.active_hist_slot))$fatal(1,"overwriting active display");
 if(kind==2&&dut.publishing&&(slot==dut.pending_cur_slot||slot==dut.pending_hist_slot))$fatal(1,"overwriting pending publication");end
 if(wait_job>0)begin wait_job=wait_job-1;if(wait_job==0)begin done=1;if(load_kind==2)begin tags[load_slot]=load_id;known[load_slot]=1;end end end
 if(req!=ack)begin ack_delay=ack_delay+1;if(ack_delay==7)begin
  if(pid==last_accepted)$fatal(1,"Duplicate publication of unchanged current frame");last_accepted=pid;
  if(ptime!==pid*40)$fatal(1,"Frame/time association changed");
  if(pid!==target||!pvalid||!pcrc||raw)$fatal(1,"publication mismatch %d %d",pid,target);
  if((pid==0&&hist)||(pid!=0&&!hist))$fatal(1,"loop must not blend last and first");
  if(!known[(cur-614400)/57600]||tags[(cur-614400)/57600]!==pid[15:0])$fatal(1,"current slot tag mismatch");
  if(hist&&(!known[(prev-614400)/57600]||tags[(prev-614400)/57600]!==pid[15:0]-16'd1))$fatal(1,"history slot tag mismatch");
  ack=req;ack_delay=0;commits=commits+1;
 end end
 if(err||alarm)$fatal(1,"manager error");
end
integer i,n;reg[31:0]last_accepted=32'hffffffff;
initial begin repeat(5)@(negedge clk);rst=0;repeat(4)@(negedge clk);
for(i=0;i<50;i=i+1)if(dut.following(i)!==((i+1)%50))$fatal(1,"wrap arithmetic");
wait(boot);
for(n=0;n<100;n=n+1)begin
 target=n%50;wait(commits>=n+1);repeat(1000)@(negedge clk);
 if(active!=target||activecrc!=target+32'h12340000)$fatal(1,"committed metadata");
end
frames=65535;repeat(3)@(negedge clk);
if(dut.following(65534)!=0||dut.following(65533)!=65534)$fatal(1,"16bit boundary");
$display("PASS manager 100 committed frames,two loops,slot protection,CRC/frame binding,first-frame no history,16bit wrap");$finish;end
initial begin #10000000;$fatal(1,"manager timeout target%d commits%d state%d",target,commits,dut.state);end
endmodule