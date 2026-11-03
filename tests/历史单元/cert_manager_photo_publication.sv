module tb;
reg clk=0;always #5 clk=~clk;reg rst=1,ack=0,done=0;wire req,start,boot,raw,pvalid,hist,pcrc;wire[1:0]kind;wire[15:0]idx;wire[31:0]pid,ptime,active,activecrc;wire[3:0]error;integer job_wait=0,ack_wait=0,commits=0;
bb_replay_manager dut(.clk(clk),.rst(rst),.playing(1'b1),.photo_mode(1'b1),.next_press(1'b0),.prev_press(1'b0),.enable(1'b1),.image_asset(1'b1),.target_frame(16'd0),.rate_q8_8(16'd256),.refresh_toggle(1'b0),.pub_ack_toggle(ack),.pub_req_toggle(req),.pub_frame_id(pid),.pub_timestamp_ms(ptime),.pub_raw(raw),.pub_valid(pvalid),.pub_history(hist),.pub_crc(pcrc),.job_start(start),.job_kind(kind),.job_index(idx),.job_done(done),.job_ok(1'b1),.job_error(4'd0),.header_valid(1'b1),.frame_count(16'd1),.nominal_fps(16'd25),.job_crc(32'h1234abcd),.job_timestamp_ms(32'd0),.boot_done(boot),.error(error),.active_frame_id(active),.active_crc(activecrc),.fast_mode(1'b0));
always @(negedge clk)if(!rst)begin
 done=0;if(start)job_wait=5;
 if(job_wait>0)begin job_wait=job_wait-1;if(job_wait==0)done=1;end
 if(req!=ack)begin ack_wait=ack_wait+1;if(ack_wait==7)begin
  if(!raw||!pvalid||!pcrc||hist||pid!=32'h80000000||ptime!=0)$fatal(1,"Photo publication corrupt");
  ack=req;ack_wait=0;commits=commits+1;
 end end
 if(error)$fatal(1,"Photo manager error");
end
initial begin repeat(5)@(negedge clk);rst=0;wait(boot);wait(commits==1);repeat(2000)@(negedge clk);
 if(commits!=1||active!=32'h80000000||activecrc!=32'h1234abcd)$fatal(1,"Photo repeated after ACK or metadata corrupt");
 $display("PASS first photo ACK does not duplicate publication,raw CRC/frame identity stable");$finish;end
initial begin #100000;$fatal(1,"Photo timeout");end
endmodule