// One contextual UI. IDs stay catalog IDs; the renderer receives a filtered list.
module alpha_ui(input clk,rst,input[3:0]short_press,long_press,repeat_press,sw,
 input catalog_ready,input[4:0]resource_count,input loading,media_ready,image_mode,
 input cue_done,input[1:0]selected_type,input selected_ready,input[15:0]image_mask,valid_mask,
 output reg[3:0]selected,output reg browser,output fullscreen,output reg[1:0]focus,display_view,
 output paused,muted,diagnostic,output reg scan,pick,next_photo,prev_photo,next_video,prev_video,step_next,step_prev,
 output reg cue_start,output reg[1:0]cue_index,output reg cue_cancel,
 output reg beep,output reg[1:0]beep_kind,output reg announcing,
 output photo_auto,output[1:0]photo_period,input opened,input[3:0]opened_index,input external_scan,
 output reg root_page,folder_images,output speed_mode,analysis_on,output[10:0]rate_q8_8,
 output[3:0]repeat_mask,output reg[47:0]list_map,output reg[3:0]list_count,selected_row,output adjust_mode,
 output keyframe_mode,output reg key_mark,key_back,key_delete);
 (* async_reg="true" *)reg[3:0]sm,ss;reg analysis_last,zoom,pause_latched,slideshow;reg[4:0]rate;
 reg[1:0]photo_queued;reg[1:0]pending_view;reg[3:0]first_item,previous_item,next_item;reg next_found,selected_found;integer i,n;
 assign analysis_on=ss[0]&&!browser&&!image_mode;
 assign speed_mode=ss[1]&&!browser&&!image_mode;
 assign fullscreen=image_mode||!analysis_on||zoom;
 assign paused=pause_latched||browser||loading||announcing||!media_ready;
 assign adjust_mode=ss[3]&&!browser;
 reg key_switch_last,key_armed;
 wire key_eligible=!browser&&!image_mode&&fullscreen&&display_view!=3;
 assign keyframe_mode=ss[2]&&key_armed&&key_eligible&&!speed_mode&&!adjust_mode;
 assign muted=1'b0;assign diagnostic=1'b0;assign photo_auto=slideshow&&!browser&&image_mode;assign photo_period=2'd2;
 assign rate_q8_8={rate,6'd0};assign repeat_mask=(speed_mode||adjust_mode) ? 4'b1100:4'd0;
 always @*begin
  list_map=0;n=0;selected_row=0;first_item=0;previous_item=selected;next_item=selected;next_found=0;selected_found=0;
  // Constant nibble shifts avoid a twelve-way variable write/barrel mux.
  for(i=11;i>=0;i=i-1)if(i<resource_count&&image_mask[i]==folder_images)
   list_map={list_map[43:0],i[3:0]};
  for(i=0;i<12;i=i+1)if(i<resource_count&&image_mask[i]==folder_images)begin
   if(n==0)first_item=i;
   if(i==selected)begin selected_row=n;selected_found=1;end
   if(i<selected)previous_item=i;
   if(i>selected&&!next_found)begin next_item=i;next_found=1;end
   n=n+1;
  end
  list_count=n;
 end
 task click;input[1:0]kind;begin beep<=1;beep_kind<=kind;end endtask
 task back_to_list;begin slideshow<=0;photo_queued<=0;browser<=1;root_page<=0;folder_images<=image_mode;zoom<=0;announcing<=0;cue_cancel<=1;click(2);end endtask
 always @(posedge clk)begin
  if(rst)begin sm<=0;ss<=0;analysis_last<=0;selected<=0;browser<=1;root_page<=1;folder_images<=0;
   zoom<=0;pause_latched<=0;slideshow<=0;rate<=4;focus<=0;display_view<=0;
   scan<=0;pick<=0;next_photo<=0;prev_photo<=0;next_video<=0;prev_video<=0;step_next<=0;step_prev<=0;
   photo_queued<=0;cue_start<=0;cue_cancel<=0;cue_index<=0;beep<=0;beep_kind<=0;announcing<=0;pending_view<=0;
   key_switch_last<=0;key_armed<=0;key_mark<=0;key_back<=0;key_delete<=0;
  end else begin
   sm<=sw;ss<=sm;analysis_last<=ss[0];scan<=0;pick<=0;next_photo<=0;prev_photo<=0;next_video<=0;prev_video<=0;
   step_next<=0;step_prev<=0;cue_start<=0;cue_cancel<=0;beep<=0;
   key_switch_last<=ss[2];key_mark<=0;key_back<=0;key_delete<=0;
   // A rise outside eligible enlarged video is discarded,not deferred.
   // A rise during SW2/SW4 retains an eligible request;their higher priority
   // releases it automatically when those switches turn off.
   if(!ss[2]||!key_eligible)key_armed<=0;
   else if(ss[2]&&!key_switch_last)begin key_armed<=1;click(0);end
   if(opened&&!browser)begin selected<=opened_index;folder_images<=image_mode;end
   if(browser&&!root_page&&catalog_ready&&list_count!=0&&!selected_found)selected<=first_item;
   if(!ss[0]||ss[0]!=analysis_last)begin zoom<=0;display_view<=0;focus<=0;
    if(ss[0]!=analysis_last)begin cue_cancel<=1;announcing<=0;click(2);end
   end
   if(external_scan&&!adjust_mode)begin slideshow<=0;browser<=1;root_page<=1;scan<=1;zoom<=0;announcing<=0;cue_cancel<=1;click(2);end
   else if(browser)begin
    slideshow<=0;
    if(short_press[0]||long_press[0])begin root_page<=1;click(2);end
    else if(root_page)begin
     if(short_press[2])begin folder_images<=0;click(0);end
     if(short_press[3])begin folder_images<=1;click(0);end
     if(short_press[1]&&catalog_ready)begin root_page<=0;selected<=first_item;click(0);end
    end else if(catalog_ready&&!loading)begin
     if(short_press[2])begin selected<=previous_item;click(previous_item==selected ? 3:0);end
     else if(short_press[3])begin selected<=next_item;click(next_item==selected ? 3:0);end
     else if(short_press[1])begin
      if(list_count!=0&&selected_ready&&valid_mask[selected]&&selected_type=={1'b0,folder_images})begin
       pick<=1;browser<=0;zoom<=0;focus<=0;display_view<=0;pause_latched<=0;rate<=4;click(0);
      end else click(3);
     end
    end
   end else if(adjust_mode)begin
    // SW4 owns keys1..4; only its physical OFF state releases this mode.
    photo_queued<=0;
   end else if(image_mode)begin
    if(short_press[0]||long_press[0])back_to_list();
    else begin
     if(long_press[1])begin slideshow<=!slideshow;click(1);end
     if(short_press[3]||short_press[2])slideshow<=0;
     if(loading||!media_ready)begin
      if(short_press[3])photo_queued<=1;else if(short_press[2])photo_queued<=2;
     end else if(short_press[3]||short_press[2]||photo_queued!=0)begin
      next_photo<=short_press[3]||(!short_press[2]&&photo_queued==1);
      prev_photo<=short_press[2]||(!short_press[3]&&photo_queued==2);
      photo_queued<=0;click(0);
     end
    end
   end else if(speed_mode)begin
    // SW2 owns this state in BOTH ordinary and analysis video views.
    // KEY1 cannot leave the file/view or clear speed mode.
    if(short_press[0]||long_press[0])click(3);
    if(!loading&&media_ready)begin
     if(short_press[1])begin pause_latched<=!pause_latched;click(1);end
     if(long_press[3]||repeat_press[3])begin if(rate<16)begin rate<=rate+1'b1;click(0);end end
     else if(long_press[2]||repeat_press[2])begin if(rate>1)begin rate<=rate-1'b1;click(0);end end
     else if(short_press[3])begin if(rate<16)begin rate<=rate>=14 ? 16:rate+2;click(0);end else click(3);end
     else if(short_press[2])begin if(rate>1)begin rate<=rate>4 ? (rate<6 ? 4:rate-2):rate-1'b1;click(0);end else click(3);end
    end
   end else if(keyframe_mode)begin
    if(!loading&&media_ready)begin
     if(short_press[1])begin pause_latched<=!pause_latched;click(1);end
     else if(short_press[3])key_mark<=1;
     else if(short_press[2])begin key_back<=1;pause_latched<=1;end
     else if(short_press[0])key_delete<=1;
    end
   end else if(!analysis_on)begin
    if(short_press[0])back_to_list();
    else if(!loading&&media_ready)begin
     if(short_press[1])begin pause_latched<=!pause_latched;click(1);end
     if(short_press[3]||short_press[2])begin pause_latched<=1;step_next<=short_press[3];step_prev<=short_press[2]&&!short_press[3];click(0);end
     if(long_press[3])begin next_video<=1;cue_cancel<=1;announcing<=0;zoom<=0;click(0);end
     else if(long_press[2])begin prev_video<=1;cue_cancel<=1;announcing<=0;zoom<=0;click(0);end
    end
   end else if(ss[0]==analysis_last)begin
    if(short_press[0])begin if(zoom||announcing)begin zoom<=0;announcing<=0;cue_cancel<=1;click(2);end else back_to_list();end
    else if(!loading&&media_ready)begin
     if(short_press[1])begin pause_latched<=!pause_latched;click(1);end
     if(zoom)begin
      // A projection of the same source timeline, not another catalog video.
      if(short_press[3]||short_press[2])begin pause_latched<=1;step_next<=short_press[3];step_prev<=short_press[2]&&!short_press[3];click(0);end
      if(long_press[3])begin display_view<=display_view+1'b1;focus<=display_view+1'b1;cue_cancel<=1;announcing<=0;click(0);end
      else if(long_press[2])begin display_view<=display_view-1'b1;focus<=display_view-1'b1;cue_cancel<=1;announcing<=0;click(0);end
     end else if(short_press[3])begin focus<=focus+1'b1;click(0);end
     else if(short_press[2])begin zoom<=1;display_view<=focus;announcing<=0;cue_cancel<=1;click(0);end
    end
   end
  end
 end
endmodule
