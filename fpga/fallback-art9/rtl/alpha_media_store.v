module alpha_media_store #(parameter CLK_HZ=100000000)(input clk,rst,job_start,input[1:0]job_kind,input[15:0]job_index,input[4:0]job_slot,
 input image_asset,input[31:0]asset_base,asset_bytes,asset_crc,input[20:0]photo_base,
 output job_done,job_ok,output[3:0]error,output busy,output[31:0]debug_status,
 output header_valid,output[15:0]frame_count,nominal_fps,output[7:0]default_threshold,output[31:0]bmp_lba,
 output[31:0]crc_actual,crc_expected,timestamp_ms,
 input card_initialized,card_busy,card_done,input[3:0]card_error,
 output card_start,output[31:0]card_lba,card_blocks,input[7:0]card_data,input card_valid,output card_ready,
 output wr_req_toggle,output[20:0]wr_base,output[19:0]wr_len,input wr_ack_toggle,wr_done_toggle,
 output[31:0]wr_data,output wr_valid,input wr_ready);
 wire vd,vo,vbusy,vhead,vstart,vready,vreq,vvalid;wire[3:0]ve;
 wire[31:0]vdebug,vbmp,vc,vec,vt,vl,vb,vdata;wire[15:0]vframes,vfps;wire[7:0]vthreshold;
 wire[20:0]vbase;wire[19:0]vlen;
 bb_object_store #(.CLK_HZ(CLK_HZ),.VIDEO_ONLY(1)) video(.clk(clk),.rst(rst),.asset_base(asset_base),.job_start(job_start&&!image_asset),.job_kind(job_kind),.job_index(job_index),.job_slot(job_slot),
 .job_done(vd),.job_ok(vo),.error(ve),.busy(vbusy),.debug_status(vdebug),.header_valid(vhead),.frame_count(vframes),.nominal_fps(vfps),.default_threshold(vthreshold),.bmp_lba(vbmp),
 .crc_actual(vc),.crc_expected(vec),.timestamp_ms(vt),.card_initialized(card_initialized),.card_busy(card_busy),.card_done(card_done&&!image_asset),.card_error(card_error),
 .card_start(vstart),.card_lba(vl),.card_blocks(vb),.card_data(card_data),.card_valid(card_valid&&!image_asset),.card_ready(vready),
 .wr_req_toggle(vreq),.wr_base(vbase),.wr_len(vlen),.wr_ack_toggle(wr_ack_toggle),.wr_done_toggle(wr_done_toggle),.wr_data(vdata),.wr_valid(vvalid),.wr_ready(wr_ready));
 wire pd,po,pbusy,pstart,pready,preq,pvalid;wire[3:0]pe;wire[31:0]pl,pb,pdata;wire[20:0]pbase;wire[19:0]plen;
 reg ph,pheader_done,pbad_job;
 always @(posedge clk)if(rst)begin ph<=0;pheader_done<=0;pbad_job<=0;end else begin pheader_done<=0;pbad_job<=image_asset&&job_start&&job_kind>1;if(image_asset&&job_start&&job_kind==0)begin ph<=1;pheader_done<=1;end end
 alpha_bmp_reader picture(.clk(clk),.rst(rst),.start(job_start&&image_asset&&job_kind==1),.lba(asset_base),.file_bytes(asset_bytes),.expected_crc(asset_crc),.destination_base(photo_base),
 .done(pd),.ok(po),.error(pe),.busy(pbusy),.initialized(card_initialized),.card_busy(card_busy),.card_done(card_done&&image_asset),.card_valid(card_valid&&image_asset),.card_data(card_data),.card_error(card_error),
 .card_start(pstart),.card_lba(pl),.card_blocks(pb),.card_ready(pready),.wr_req_toggle(preq),.wr_base(pbase),.wr_len(plen),.wr_ack_toggle(wr_ack_toggle),.wr_done_toggle(wr_done_toggle),.wr_data(pdata),.wr_valid(pvalid),.wr_ready(wr_ready));
 assign job_done=image_asset ? (pd||pheader_done||pbad_job):vd;assign job_ok=image_asset ? (po||pheader_done)&&!pbad_job:vo;assign error=image_asset ? (pbad_job ? 4'hb:pe):ve;
 assign busy=image_asset ? pbusy:vbusy;assign debug_status=image_asset ? {24'd0,pe,3'd0,pbusy}:vdebug;
 assign header_valid=image_asset ? ph:vhead;assign frame_count=image_asset ? 16'd1:vframes;assign nominal_fps=image_asset ? 16'd1:vfps;
 assign default_threshold=image_asset ? 8'd24:vthreshold;assign bmp_lba=image_asset ? asset_base:vbmp;
 assign crc_actual=image_asset ? asset_crc:vc;assign crc_expected=image_asset ? asset_crc:vec;assign timestamp_ms=image_asset ? 0:vt;
 assign card_start=image_asset ? pstart:vstart;assign card_lba=image_asset ? pl:vl;assign card_blocks=image_asset ? pb:vb;assign card_ready=image_asset ? pready:vready;
 assign wr_req_toggle=image_asset ? preq:vreq;assign wr_base=image_asset ? pbase:vbase;assign wr_len=image_asset ? plen:vlen;
 assign wr_data=image_asset ? pdata:vdata;assign wr_valid=image_asset ? pvalid:vvalid;
endmodule
