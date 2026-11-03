// Registered four-pane shader. TL and full-screen video are untouched RGB.
// TR adds frame-matched component edges, BL shows a denoised binary mask,
// BR contains all labels, progress and status. No HUD covers the clean pane.
module bb_forensic_osd(input clk,rst,hs,vs,de,input[9:0]screenx,input[8:0]screeny,
 input[23:0]rgb,night_rgb,input quad_mode,raw_mode,mask_bit,
 input[3:0]boxes_valid,input[111:0]boxes,input[1:0]scene,
 input playing,auto_slow,diagnostic,alarm,crc_ok,input[1:0]menu,input[71:0]boot_diag,input[3:0]error,
 input[31:0]frame_id,timestamp_ms,input[15:0]frame_count,media_fps,new_fps,hdmi_fps,rate_q8_8,
 input[7:0]threshold,input[1:0]gamma,input[5:0]cache_ready,
 input[31:0]energy,underflows,late_count,input[18:0]motion_count,
 output reg ohs,ovs,ode,output reg[23:0]out_rgb);
 wire q=quad_mode&&!raw_mode;wire[8:0]lx=screenx>=320?screenx-320:screenx;
 wire[7:0]ly=screeny>=240?screeny-240:screeny;
 reg edge_hit;reg[6:0]l,r,t,b;integer k;
 always @*begin edge_hit=0;l=0;r=0;t=0;b=0;
  for(k=0;k<4;k=k+1)begin
   l=boxes[k*28+:7];r=boxes[k*28+7+:7];t=boxes[k*28+14+:7];b=boxes[k*28+21+:7];
   if(boxes_valid[k]&&lx>={l,2'b0}&&lx<={r,2'b11}&&ly>={t,2'b0}&&ly<={b,2'b11}&&
    (lx=={l,2'b0}||lx=={r,2'b11}||ly=={t,2'b0}||ly=={b,2'b11}))edge_hit=1;
  end
 end
 reg[39:0]fbcd,tbcd,fw,tw,fa,ta;reg[31:0]fs,ts,last_f,last_t;reg[5:0]left;reg metadata;
 reg[31:0]progress_work;reg[8:0]progress,progress_temp;reg progress_busy;
 reg[23:0]speed_work;reg[15:0]speed_den,last_rate,last_fps;reg[11:0]speed_temp,speed_tenths;reg speed_busy;
 integer j;
 always @*begin fa=fw;ta=tw;for(j=0;j<10;j=j+1)begin
  if(fw[j*4+:4]>=5)fa[j*4+:4]=fw[j*4+:4]+3;if(tw[j*4+:4]>=5)ta[j*4+:4]=tw[j*4+:4]+3;end end
 always @(posedge clk)begin
  if(rst)begin fbcd<=0;tbcd<=0;fw<=0;tw<=0;fs<=0;ts<=0;last_f<=0;last_t<=0;left<=0;metadata<=0;
   progress<=0;progress_temp<=0;progress_busy<=0;progress_work<=0;speed_work<=0;speed_den<=1;
   last_rate<=0;last_fps<=0;speed_temp<=0;speed_tenths<=0;speed_busy<=0;
  end else begin
   if(!metadata||last_f!=frame_id||last_t!=timestamp_ms)begin
    metadata<=1;last_f<=frame_id;last_t<=timestamp_ms;fw<=0;tw<=0;fs<=frame_id;ts<=timestamp_ms;left<=32;
    progress_work<=raw_mode?0:frame_id*32'd300;progress_temp<=0;progress_busy<=1;
   end else if(left!=0)begin fw<={fa[38:0],fs[31]};tw<={ta[38:0],ts[31]};fs<=fs<<1;ts<=ts<<1;left<=left-1'b1;
    if(left==1)begin fbcd<={fa[38:0],fs[31]};tbcd<={ta[38:0],ts[31]};end
   end
   if(progress_busy)begin
    if(frame_count<=1||progress_work<frame_count-1'b1||progress_temp==300)begin progress<=progress_temp;progress_busy<=0;end
    else begin progress_work<=progress_work-(frame_count-1'b1);progress_temp<=progress_temp+1'b1;end
   end
   if(last_rate!=rate_q8_8||last_fps!=media_fps)begin
    last_rate<=rate_q8_8;last_fps<=media_fps;speed_work<=rate_q8_8*24'd10;speed_den<=media_fps<<8;speed_temp<=0;speed_busy<=1;
   end else if(speed_busy)begin
    if(speed_den==0||speed_work<speed_den||speed_temp==999)begin speed_tenths<=speed_temp;speed_busy<=0;end
    else begin speed_work<=speed_work-speed_den;speed_temp<=speed_temp+1'b1;end
   end
  end
 end
 function[7:0]digit;input[3:0]v;begin digit=v<10?48+v:55+v;end endfunction
 function[7:0]txt;input[3:0]row;input[4:0]col;reg[191:0]s;begin
  s="                        ";
  case(row)
   0:s="FORENSIC / VIDEO        ";
   1:s=playing?(auto_slow&&alarm?"SLOW    SPEED:          ":"PLAY    SPEED:          "):"STEP/PAUSE SPEED:       ";
   2:s="FRAME:                  ";
   3:s="TIME MS:                ";
   4:s="MEDIA:     NEW:         ";
   5:s="HDMI:        FPS        ";
   6:s=crc_ok?"CRC32: OK [VERIFIED]    ":"CRC32: WAIT / FAIL      ";
   7:case(scene)1:s="LIGHT CHANGE / NO BOX   ";2:s="CAMERA MOTION / NO BOX  ";3:s="REGION OVERFLOW         ";default:s=alarm?"EVENT LATCHED           ":auto_slow?"AUTO SLOW: ARMED        ":"AUTO SLOW: OFF          ";endcase
   8:s=diagnostic?"UND:       LATE:        ":"THRESH:    CACHE:       ";
   9:s=diagnostic?"ERR:     ENERGY:        ":"SW1: FULL / QUAD        ";
  endcase
  if(row==0&&raw_mode)s="PHOTO ALBUM / BMP       ";
  if(row==0&&menu!=0)case(menu)
   1:s="SET THRESH / KEY2+ KEY3-";2:s="SET GAMMA / KEY2+ KEY3- ";3:s="SET RATE / KEY2+ KEY3-  ";endcase
  if(row==9&&menu!=0)s="KEY4 NEXT / HOLDKEY3 EXI";
  if(diagnostic)case(row)
   0:s="BOOT DIAG V2 / READ HEX ";
   1:s="SD:  00000000           ";
   2:s="OBJ: 00000000           ";
   3:s="MEM: 00   ERR:0         ";
   4:s="SDI:0 RAM:0 HDR:0       ";
   6:if(!crc_ok)s="VIDEO FRAME NOT READY   ";
   8:s="RX:0 NIB:000 V:0 R:0    ";
   9:s="ST:0 K:0 POS:00000      ";
  endcase
  txt=s>>((23-col)*8);
  if(row==0&&raw_mode&&col==12)txt=49+frame_id[1:0];
  if(row==1&&!diagnostic)begin
    if(col==14)txt=digit((speed_tenths/100)%10);if(col==15)txt=digit((speed_tenths/10)%10);if(col==16)txt=".";if(col==17)txt=digit(speed_tenths%10);if(col==18)txt="X";
  end
  if(!diagnostic&&row==2&&col>=7&&col<17)txt=digit((fbcd>>((16-col)*4))&15);
  if(!diagnostic&&row==3&&col>=9&&col<19)txt=digit((tbcd>>((18-col)*4))&15);
  if(row==4&&!diagnostic)begin
   if(col==7)txt=digit((media_fps/10)%10);if(col==8)txt=digit(media_fps%10);
   if(col==15)txt=digit((new_fps[15:8]/10)%10);if(col==16)txt=digit(new_fps[15:8]%10);
  end
  if(row==5)begin if(col==6)txt=digit((hdmi_fps[15:8]/10)%10);if(col==7)txt=digit(hdmi_fps[15:8]%10);end
  if(row==8&&!diagnostic)begin
   if(col==8)txt=digit(threshold/100);if(col==9)txt=digit((threshold/10)%10);if(col==10)txt=digit(threshold%10);
   if(col==18)txt=digit(cache_ready/10);if(col==19)txt=digit(cache_ready%10);
  end
  if(diagnostic)begin
   if(row==1&&col>=5&&col<13)txt=digit((boot_diag[71:40]>>((12-col)*4))&15);
   if(row==2&&col>=5&&col<13)txt=digit((boot_diag[39:8]>>((12-col)*4))&15);
   if(row==3&&col==5)txt=digit(boot_diag[7:4]);
   if(row==3&&col==6)txt=digit(boot_diag[3:0]);
   if(row==3&&col==14)txt=digit(error);
   if(row==4&&col==4)txt=48+boot_diag[33];
   if(row==4&&col==10)txt=48+boot_diag[7];
   if(row==4&&col==16)txt=48+boot_diag[34];
   if(row==8&&col==3)txt=digit({1'b0,boot_diag[65:63]});
   if(row==8&&col==9)txt=digit({2'b0,boot_diag[62:61]});
   if(row==8&&col==10)txt=digit(boot_diag[60:57]);
   if(row==8&&col==11)txt=digit(boot_diag[56:53]);
   if(row==8&&col==15)txt=48+boot_diag[52];
   if(row==8&&col==19)txt=48+boot_diag[51];
   if(row==9&&col==3)txt=digit({1'b0,boot_diag[39:37]});
   if(row==9&&col==7)txt=digit({2'b0,boot_diag[36:35]});
   if(row==9&&col>=13&&col<18)txt=digit((boot_diag[27:8]>>((17-col)*4))&15);
  end
 end endfunction
 reg[7:0]character;reg[2:0]fr,fc;wire font_pixel;reg[7:0]ch_stage;reg[2:0]fr_stage,fc_stage;
 reg text_stage;reg[23:0]base_stage,ink_stage;reg[2:0]sync_stage;
 bb_font5x7 font(ch_stage,fr_stage,fc_stage,font_pixel);
 reg[23:0]color;reg text_on;reg[3:0]row;reg[4:0]col;
 always @*begin
  color=rgb;text_on=0;character=32;fr=0;fc=0;row=0;col=0;
  if(q)begin
   if(screeny<240&&screenx>=320)begin color=gamma==0?rgb:night_rgb;if(edge_hit)color=24'h00ff00;end
   if(screeny>=240&&screenx<320)color=mask_bit?24'hffffff:24'h000000;
   if(screeny>=240&&screenx>=320)begin
    color=24'h101a24;
    if(lx>=10&&lx<310&&ly>=216&&ly<230)color=lx-10<progress?24'h42a9d6:24'h263a4b;
    if(lx>=10&&lx<298&&ly>=8&&ly<208)begin
     row=(ly-8)/20;col=(lx-10)/12;fr=((ly-8)%20)>>1;fc=((lx-10)%12)>>1;
     if((ly-8)%20<14)begin character=txt(row,col);text_on=1;end
    end

   end
  end
  // Album/menu is an explicit user-selected screen. A small named banner
  // prevents long-press album from being mistaken for low-FPS video.
  if((raw_mode&&screeny<20)||(!q&&menu!=0&&screeny<40))begin
   color=24'h101a24;
   if(screenx<288&&(screeny%20)<14)begin
    col=screenx/12;row=screeny<20?0:8;fr=(screeny%20)>>1;fc=(screenx%12)>>1;character=txt(row,col);text_on=1;
   end
  end
 end
 always @(posedge clk)begin
  if(rst)begin ohs<=0;ovs<=0;ode<=0;out_rgb<=0;ch_stage<=32;fr_stage<=0;fc_stage<=0;text_stage<=0;base_stage<=0;ink_stage<=0;sync_stage<=0;end
  else begin
   ch_stage<=character;fr_stage<=fr;fc_stage<=fc;text_stage<=text_on;base_stage<=color;sync_stage<={hs,vs,de};
   ink_stage<=row==6?(crc_ok?24'h68ef9e:24'hff7060):row==7&&alarm?24'hff7060:24'hd9e8f0;
   ohs<=sync_stage[2];ovs<=sync_stage[1];ode<=sync_stage[0];out_rgb<=!sync_stage[0]?24'd0:text_stage&&font_pixel?ink_stage:base_stage;
  end
 end
endmodule
