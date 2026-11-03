module tb;
reg clk=0;always #20 clk=~clk;reg rst=1,fs=0,de=0,full=0,browser=0;reg[1:0]view=0;reg[9:0]x=0;reg[8:0]y=0;
reg[23:0]cur=0,next=0;wire[4:0]namechar;wire[7:0]query;wire[3:0]nameitem;wire[7:0]bar,peak;wire[15:0]level;wire fftupdated;wire[31:0]skip;
reg sv=0;reg[15:0]pcm=0;wire h,v,d;wire[23:0]rgb;wire[31:0]bcd;
assign bar=0;assign peak=0;assign level=0;
wire[7:0]wq;wire signed[15:0]wmin,wmax;wire wvalid;
assign wmin=0;assign wmax=0;assign wvalid=0;reg image_mode=0;reg[3:0]keycode=0;
alpha_views dut(.clk(clk),.rst(rst),.frame_start(fs),.hs(1'b1),.vs(1'b1),.de(de),.x(x),.y(y),.current_rgb(cur),.next_rgb(next),.pair_valid(1'b1),.phase(8'd128),.fullscreen(full),.view(view),.focus(2'd1),
 .browser(browser),.loading(1'b0),.paused(1'b0),.muted(1'b0),.has_audio(1'b1),.diagnostic(1'b0),.announcing(1'b0),.image_mode(image_mode),.photo_auto(1'b0),.adjust_mode(1'b0),.adjust_item(2'd0),.exposure(8'd50),.contrast(8'd50),.brightness(8'd50),.volume(8'd20),.wave_energy(8'd0),.wave_bins(9'd0),.box_frame(16'd90),.keyframe_mode(1'b1),.keyframe_count(3'd4),.keyframe_frames(64'h00960078003c001e),.keyframe_result(keycode),.source_frames(16'd180),.error(4'd0),.selected(4'd1),.resource_count(5'd4),.valid_mask(16'h000f),.image_mask(16'h000c),.name_item(nameitem),.name_char(namechar),.name_data(8'h41),
 .media_ms(32'd3000),.duration_ms(32'd6000),.frame_id(16'd90),.source_width(16'd640),.source_height(16'd480),.boxes_valid(4'd0),.boxes(112'h000000000000000000002850a),.bar_value(bar),.peak_bin(peak),.peak_level(level),.audio_underflows(32'd0),.bar_query(query),.ohs(h),.ovs(v),.ode(d),.rgb(rgb),.formatted_time(bcd),.root_page(1'b0),.folder_images(1'b0),.speed_mode(1'b0),.analysis_on(1'b1),.rate_q8_8(11'd256),.list_map(48'h543210),.list_count(4'd4),.selected_row(4'd1),.wave_min(wmin),.wave_max(wmax),.wave_valid(wvalid),.wave_query(wq));
reg[15:0]tone[0:255];integer i,j,f,n=0;reg capture=0;integer lx,ly;
always @(posedge clk)begin #1;if(capture&&d)begin $fwrite(f,"%c%c%c",rgb[23:16],rgb[15:8],rgb[7:0]);n=n+1;end end
task tick;begin @(negedge clk);end endtask
task raster;input[255:0]name;begin
 fs=1;tick;fs=0;repeat(1000)tick;f=$fopen(name,"wb");$fwrite(f,"P6\n640 480\n255\n");capture=1;n=0;
 for(j=0;j<480;j=j+1)begin
  for(i=0;i<640;i=i+1)begin
   x=i;y=j;de=1;lx=full?i:i%320;ly=full?j:j%240;
   cur={lx[7:0],ly[7:0],8'd16};next={(lx[7:0]+8'd20),ly[7:0],8'd40};tick;
  end
  de=0;repeat(160)tick;
 end
 repeat(10)tick;capture=0;$fclose(f);if(n!=307200)$fatal(1,"raster count%d",n);
 if(bcd!=32'h00000300)$fatal(1,"time format%h",bcd);
end endtask


integer code;reg[239:0]expected="READYFULL DUP  NONE BUSY WAIT ";reg[7:0]want;
initial begin repeat(5)tick;rst=0;full=1;view=0;de=1;
for(code=0;code<6;code=code+1)for(j=0;j<5;j=j+1)begin
 keycode=code;x=32+(8+j)*8;y=400;repeat(6)tick;want=expected[239-(code*5+j)*8-:8];
 if(dut.character!==(16'h8000|(50<<5)|(code*5+j))||dut.text_memory[dut.character[10:0]]!==want)$fatal(1,"status text/ROM address mismatch code%d char%d got%x want%x",code,j,dut.character,want);
end
$display("PASS READY/FULL/DUP/NONE/BUSY/WAIT all30 glyph positions through real shared text ROM;no truncated arithmetic index");$finish;end
endmodule