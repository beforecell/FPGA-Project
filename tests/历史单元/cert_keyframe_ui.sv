module tb;
reg clk=0;always #5 clk=~clk;reg rst=1;reg[3:0]s=0,l=0,r=0,sw=0;
wire[3:0]selected;wire browser,full,paused,muted,adjust,speed,analysis,kf,mark,back,del;
wire[1:0]view,focus;wire[10:0]rate;wire pick,np,pp,nv,pv,sn,sp,root,folder;
alpha_ui dut(.clk(clk),.rst(rst),.short_press(s),.long_press(l),.repeat_press(r),.sw(sw),.catalog_ready(1'b1),.resource_count(5'd6),.loading(1'b0),.media_ready(1'b1),.image_mode(1'b0),.cue_done(1'b0),.selected_type(2'd0),.selected_ready(1'b1),.image_mask(16'h003c),.valid_mask(16'h003f),
.selected(selected),.browser(browser),.fullscreen(full),.focus(focus),.display_view(view),.paused(paused),.muted(muted),.pick(pick),.next_photo(np),.prev_photo(pp),.next_video(nv),.prev_video(pv),.step_next(sn),.step_prev(sp),.opened(1'b0),.opened_index(4'd0),.external_scan(1'b0),.root_page(root),.folder_images(folder),.speed_mode(speed),.analysis_on(analysis),.rate_q8_8(rate),.adjust_mode(adjust),.keyframe_mode(kf),.key_mark(mark),.key_back(back),.key_delete(del));
task tick;input integer n;begin repeat(n)@(negedge clk);end endtask
task key;input integer n;begin s=1<<(n-1);tick(1);s=0;tick(1);end endtask
task rise;begin sw[2]=0;tick(6);sw[2]=1;tick(6);end endtask
initial begin
 sw=4;tick(5);rst=0;tick(8);if(kf)$fatal(1,"root accepted SW3");key(2);key(2);tick(6);
 if(browser||!full||kf)$fatal(1,"held root SW3 activated on open");rise;if(!kf||muted)$fatal(1,"full rise or replaced mute");
 s=8;tick(1);s=0;if(!mark||sn||nv)$fatal(1,"KEY4 not mark-only");tick(2);
 s=4;tick(1);s=0;if(!back||sp||pv||!paused)$fatal(1,"KEY3 not back/pause");tick(2);
 s=1;tick(1);s=0;if(!del||browser)$fatal(1,"KEY1 exited keyframe mode");tick(2);key(2);if(paused)$fatal(1,"KEY2 resume");
 sw[1]=1;tick(6);if(kf||!speed)$fatal(1,"SW2 priority");key(1);if(browser)$fatal(1,"speed KEY1 exit");
 sw[1]=0;tick(6);if(!kf)$fatal(1,"eligible held SW3 not restored after SW2");
 sw[3]=1;tick(6);if(kf||!adjust)$fatal(1,"SW4 priority");key(1);if(del||browser)$fatal(1,"adjust key leaked");sw[3]=0;tick(6);if(!kf)$fatal(1,"SW4 return");
 sw[2]=0;sw[0]=1;tick(8);if(full||kf)$fatal(1,"SW1 did not quad");rise;if(kf)$fatal(1,"quad accepted SW3");
 key(3);tick(4);if(!full||kf)$fatal(1,"ignored quad rise activated on zoom");rise;if(!kf)$fatal(1,"retoggle in enlarged view");
 sw[2]=0;tick(6);l=8;tick(1);l=0;tick(2);l=8;tick(1);l=0;tick(2);l=8;tick(1);l=0;tick(2);
 if(view!=3)$fatal(1,"audio view setup");rise;if(kf)$fatal(1,"audio view accepted SW3");l=4;tick(1);l=0;tick(3);if(view!=2||kf)$fatal(1,"held invalid rise activated on view change");
 sw[2]=0;sw[1]=1;tick(6);sw[2]=1;tick(6);if(kf||!speed)$fatal(1,"SW3 during speed");sw[1]=0;tick(6);if(!kf)$fatal(1,"SW2 OFF failed deferred eligible SW3");
 sw[0]=0;tick(6);if(!kf||!full||view!=0)$fatal(1,"ordinary full same-timeline mode lost");
 sw[2]=0;tick(6);s=8;tick(1);s=0;if(!sn||mark||!paused)$fatal(1,"normal step not restored");tick(2);key(1);if(!browser)$fatal(1,"normal exit not restored");
 $display("PASS SW3 eligibility edges,quad/audio/root ignored rises,retoggle,SW4>SW2>keyframes,SW2-deferred activation,mark/back/delete/pause,ordinary key restoration,SW3 no mute");$finish;
end
endmodule