module alpha_media_control(input clk,rst,pick,next_photo,prev_photo,auto_next,input[3:0]ui_selected,
 input next_video,prev_video,input[4:0]count,input[15:0]valid_mask,image_mask,input selected_ready,input[1:0]kind,
 input[31:0]q_lba,q_bytes,q_crc,q_audio_lba,q_audio_samples,q_duration,input[15:0]q_width,q_height,
 input io_idle,boot_done,input[3:0]manager_error,
 output[3:0]query_index,output reg active_valid,image_asset,output reg[3:0]active_index,
 output reg[31:0]asset_lba,asset_bytes,asset_crc,audio_lba,audio_samples,duration_ms,
 output reg[15:0]width,height,output loading,enable,output reg media_reset,audio_restart,opened);
 reg[3:0]state;reg[3:0]target;reg[6:0]delay_count;reg backwards,search_images;reg[4:0]attempts;
 assign query_index=state==0||state==4||state==5 ? ui_selected:target;
 assign loading=state!=0&&state!=4&&state!=5;assign enable=state==3||state==4;
 always @(posedge clk)begin
  if(rst)begin state<=0;target<=0;delay_count<=0;active_valid<=0;image_asset<=0;active_index<=0;asset_lba<=0;asset_bytes<=0;asset_crc<=0;audio_lba<=0;audio_samples<=0;duration_ms<=0;width<=640;height<=480;
   media_reset<=0;audio_restart<=0;opened<=0;backwards<=0;search_images<=0;attempts<=0;
  end else begin
   audio_restart<=0;opened<=0;
   if((state==0||state==4||state==5)&&pick)begin target<=ui_selected;state<=1;end
   else if(state==4&&((image_asset&&(next_photo||prev_photo||auto_next))||(!image_asset&&(next_video||prev_video))))begin target<=active_index;search_images<=image_asset;backwards<=image_asset ? prev_photo:prev_video;attempts<=0;state<=6;end
   else case(state)
    1:if(selected_ready&&io_idle)begin
     if(kind<2)state<=8;else state<=5;
    end
    8:begin
      active_index<=target;asset_lba<=q_lba;asset_bytes<=q_bytes;asset_crc<=q_crc;audio_lba<=q_audio_lba;audio_samples<=q_audio_samples;duration_ms<=q_duration;width<=q_width;height<=q_height;
      active_valid<=1;image_asset<=kind==1;media_reset<=1;delay_count<=0;state<=2;opened<=1;
    end
    2:begin
     delay_count<=delay_count+1'b1;
     if(delay_count==63)media_reset<=0;
     if(delay_count==95)begin audio_restart<=1;state<=3;end
    end
    3:if(boot_done)state<=4;else if(manager_error!=0)state<=5;
    6:begin target<=backwards ? (target==0 ? count-1'b1:target-1'b1):(target+1>=count ? 0:target+1'b1);attempts<=attempts+1'b1;state<=7;end
    7:if(image_mask[target]==search_images&&valid_mask[target])state<=1;else if(attempts>=count)state<=4;else state<=6;
    default:;
   endcase
  end
 end
endmodule
