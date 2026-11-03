module top(input wire clk,input wire rst_n,
 input wire phy1_rgmii_rx_clk,input wire phy1_rgmii_rx_ctl,input wire[3:0]phy1_rgmii_rx_data,
 output wire phy1_rgmii_tx_clk,output wire phy1_rgmii_tx_ctl,output wire[3:0]phy1_rgmii_tx_data,
 output wire[3:0]led,output wire sd_dclk,inout wire sd_cmd,inout wire[3:0]sd_dat);
 localparam DEVICE="EG4";
 localparam LOCAL_MAC_ADDRESS=48'h02_48_58_34_53_20;
 localparam LOCAL_IP_ADDRESS=32'hffffffff; //unconfigured broadcast bootstrap;HELLO selects a unicast address
 localparam LOCAL_UDP_PORT_NUM=16'd49192;
 wire[31:0]DST_IP_ADDRESS;
 wire[15:0]DST_UDP_PORT_NUM;
 reg[19:0]boot=0;reg[1:0]rs=0;
 always @(posedge clk)begin if(boot!=20'hfffff)boot<=boot+1'b1;rs<={rs[0],rst_n};end
 wire txlocked;wire reset=boot!=20'hfffff||!rs[1]||!txlocked;
 wire clk_125_out,temac_clk90;
 pll_gen u_tx_pll(.refclk(clk),.reset(1'b0),.extlock(txlocked),.clk0_out(clk_125_out),.clk1_out(),.clk2_out(),.clk3_out(),.clk4_out(temac_clk90));
 wire udp_clk=clk;
 reg[2:0]txrs=3'b111,rxrs=3'b111;
 always @(posedge clk_125_out or posedge reset)if(reset)txrs<=3'b111;else txrs<={txrs[1:0],1'b0};
 always @(posedge phy1_rgmii_rx_clk_90 or posedge reset)if(reset)rxrs<=3'b111;else rxrs<={rxrs[1:0],1'b0};
 wire tx_reset=txrs[2],rx_reset=rxrs[2];
 wire[31:0]input_local_ip_address;wire input_local_ip_address_valid=1;
 wire[15:0]input_local_udp_port_num=LOCAL_UDP_PORT_NUM;wire input_local_udp_port_num_valid=1;
 wire app_rx_data_valid;wire[7:0]app_rx_data;wire[15:0]app_rx_data_length,app_rx_port_num;
 wire udp_tx_ready,app_tx_ack,app_tx_data_request,app_tx_data_valid;wire[7:0]app_tx_data;wire[15:0]udp_data_length;
 wire[7:0]temac_tx_data,temac_rx_data,tx_data,rx_data;
 wire temac_tx_valid,temac_tx_sof,temac_tx_eof,temac_tx_ready;
 wire temac_rx_valid,temac_rx_sof,temac_rx_eof,temac_rx_ready;
 wire rx_clk_int,rx_clk_en_int,tx_clk_int,tx_clk_en_int,rx_valid,tx_valid,tx_rdy,tx_collision,tx_retransmit,rx_correct_frame,rx_error_frame;
 wire[1:0]TRI_speed=2'b10;
 wire tx_stop=0;wire[7:0]tx_ifg_val=0;wire pause_req=0;wire[15:0]pause_val=0;wire[47:0]pause_source_addr=48'h02_48_58_34_53_20;
 wire[47:0]unicast_address={LOCAL_MAC_ADDRESS[7:0],LOCAL_MAC_ADDRESS[15:8],LOCAL_MAC_ADDRESS[23:16],LOCAL_MAC_ADDRESS[31:24],LOCAL_MAC_ADDRESS[39:32],LOCAL_MAC_ADDRESS[47:40]};
 wire[19:0]mac_cfg_vector={1'b0,2'b00,TRI_speed,8'b00000010,7'b0000010};
 reg[27:0]tick=0;reg[31:0]rxcount=0,txcount=0;
 always @(posedge clk)begin tick<=tick+1'b1;if(app_rx_data_valid)rxcount<=rxcount+1'b1;if(app_tx_data_valid)txcount<=txcount+1'b1;end
 assign led={sd_error!=0,core_armed,tick[25],sd_initialized};

 wire[7:0]crx,ctx,sd_data,sd_wdata;wire crv,ctv,ctr,core_armed,core_active,core_fault,sd_soft_reset;
 wire sd_start,sd_write,sd_initialized,sd_busy,sd_done,sd_valid;wire[31:0]sd_lba,discarded,sd_debug1,sd_debug2,net_dropped,net_accepted;
 wire[3:0]sd_error;wire[127:0]cid,csd;wire[63:0]sectors;wire[8:0]sd_waddr;wire[4:0]net_queued;
 network_bridge netapp(.clk(clk),.rst(reset),.rx_data(app_rx_data),.rx_valid(app_rx_data_valid),.rx_length(app_rx_data_length),
 .udp_tx_ready(udp_tx_ready),.udp_tx_ack(app_tx_ack),.tx_data(app_tx_data),.tx_valid(app_tx_data_valid),.tx_request(app_tx_data_request),.tx_length(udp_data_length),
 .local_ip(input_local_ip_address),.peer_ip(DST_IP_ADDRESS),.peer_port(DST_UDP_PORT_NUM),.core_rx_data(crx),.core_rx_valid(crv),.core_tx_data(ctx),.core_tx_valid(ctv),.core_tx_ready(ctr),
 .core_armed(core_armed),.sd_ready(sd_initialized),.sd_error(sd_error),.core_fault_reset(core_fault),.dropped(net_dropped),.accepted(net_accepted),.queued(net_queued));
 tf_bridge_core #(.BAUD(0)) core(clk,reset|core_fault,crx,crv,ctx,ctv,ctr,sd_start,sd_write,sd_lba,
 sd_initialized,sd_busy,sd_done,sd_error,cid,csd,sectors,sd_data,sd_valid,sd_waddr,sd_wdata,sd_soft_reset,core_armed,core_active,discarded,sd_debug1,sd_debug2);
 sd_maint4 sd(.clk(clk),.rst(reset|core_fault|sd_soft_reset),.start(sd_start),.lba(sd_lba),.blocks(32'd1),
 .write_op(sd_write),.write_addr(sd_waddr),.write_data(sd_wdata),.cid(cid),.csd(csd),.sector_count(sectors),
 .initialized(sd_initialized),.busy(sd_busy),.done(sd_done),.error(sd_error),.data(sd_data),.valid(sd_valid),.ready(1'b1),
 .debug_status(sd_debug1),.debug_data(sd_debug2),.sd_clk(sd_dclk),.sd_cmd(sd_cmd),.sd_dat(sd_dat));
//------------------------------------------------------------  
//UDP
//------------------------------------------------------------       
udp_ip_protocol_stack #
(
    .DEVICE                     (DEVICE                 ),
    .LOCAL_UDP_PORT_NUM         (LOCAL_UDP_PORT_NUM     ),
    .LOCAL_IP_ADDRESS           (LOCAL_IP_ADDRESS       ),
    .LOCAL_MAC_ADDRESS          (LOCAL_MAC_ADDRESS      )
)   
u3_udp_ip_protocol_stack    
(   
    .udp_rx_clk                 (udp_clk                ),
    .udp_tx_clk                 (udp_clk                ),
    .reset                      (reset                  ), 
    .udp2app_tx_ready           (udp_tx_ready           ), 
    .udp2app_tx_ack             (app_tx_ack             ), 
    .app_tx_request             (app_tx_data_request    ), 
    .app_tx_data_valid          (app_tx_data_valid      ), 
    .app_tx_data                (app_tx_data            ), 
    .app_tx_data_length         (udp_data_length        ), 
    .app_tx_dst_port            (DST_UDP_PORT_NUM       ), 
    .ip_tx_dst_address          (DST_IP_ADDRESS         ), 
    
    .input_local_udp_port_num      (input_local_udp_port_num      ),
    .input_local_udp_port_num_valid(input_local_udp_port_num_valid),
    
    .input_local_ip_address     (input_local_ip_address     ),
    .input_local_ip_address_valid(input_local_ip_address_valid),
    
    .app_rx_data_valid          (app_rx_data_valid      ), 
    .app_rx_data                (app_rx_data            ), 
    .app_rx_data_length         (app_rx_data_length     ), 
    .app_rx_port_num            (app_rx_port_num        ), 
    .temac_rx_ready             (temac_rx_ready         ),//output
    .temac_rx_valid             (!temac_rx_valid        ),//input
    .temac_rx_data              (temac_rx_data          ),//input
    .temac_rx_sof               (temac_rx_sof           ),//input
    .temac_rx_eof               (temac_rx_eof           ),//input
    .temac_tx_ready             (temac_tx_ready         ),//input
    .temac_tx_valid             (temac_tx_valid         ),//output
    .temac_tx_data              (temac_tx_data          ),//output
    .temac_tx_sof               (temac_tx_sof           ),//output
    .temac_tx_eof               (temac_tx_eof           ),//output
`ifdef DEBUG_UDP
    .udp_debug_out              (udp_debug_out          ),
`endif
    .ip_rx_error                (                       ), 
    .arp_request_no_reply_error (                       )
);
wire phy1_rgmii_rx_clk_0;
wire phy1_rgmii_rx_clk_90;
rx_pll u_rx_pll(
	.refclk		(phy1_rgmii_rx_clk),
    .reset  (1'b0),
    .clk0_out	(phy1_rgmii_rx_clk_0),
	.clk1_out	(phy1_rgmii_rx_clk_90)
);
//------------------------------------------------------------  
//TEMAC
//------------------------------------------------------------  
temac_block#(
    .P_ADD_FILT_EN         (1'b0                     ), //receive UDP discovery broadcasts
    .DEVICE               (DEVICE                   )
)  
u4_trimac_block
(
    .reset                (reset                    ),
    .gtx_clk              (clk_125_out                ),//input   125M
    .gtx_clk_90           (temac_clk90                ),//input   125M
    .rx_clk               (rx_clk_int               ),//output  125M 25M    2.5M
    .rx_clk_en            (rx_clk_en_int            ),//output  1    12.5M  1.25M
    .rx_data              (rx_data                  ),
    .rx_data_valid        (rx_valid                 ),
    .rx_correct_frame     (rx_correct_frame         ),
    .rx_error_frame       (rx_error_frame           ),
    .rx_status_vector     (                         ),
    .rx_status_vld        (                         ),
//  .tri_speed            (tri_speed                ),//output
    .tx_clk               (tx_clk_int               ),//output  125M
    .tx_clk_en            (tx_clk_en_int            ),//output  1    12.5M  1.25M 占空比不对
    .tx_data              (tx_data                  ),
    .tx_data_en           (tx_valid                 ),
    .tx_rdy               (tx_rdy                   ),//temac_tx_ready
    .tx_stop              (tx_stop                  ),//input
    .tx_collision         (tx_collision             ),
    .tx_retransmit        (tx_retransmit            ),
    .tx_ifg_val           (tx_ifg_val               ),//input
    .tx_status_vector     (                         ),
    .tx_status_vld        (                         ),
    .pause_req            (pause_req                ),//input
    .pause_val            (pause_val                ),//input
    .pause_source_addr    (pause_source_addr        ),//input
    .unicast_address      (unicast_address          ),//input
    .mac_cfg_vector       (mac_cfg_vector           ),//input
    .rgmii_txd            (phy1_rgmii_tx_data       ),
    .rgmii_tx_ctl         (phy1_rgmii_tx_ctl        ),
    .rgmii_txc            (phy1_rgmii_tx_clk        ),
    .rgmii_rxd            (phy1_rgmii_rx_data       ),
    .rgmii_rx_ctl         (phy1_rgmii_rx_ctl        ),
    .rgmii_rxc            (phy1_rgmii_rx_clk_90        ),
    .inband_link_status   (                         ),
    .inband_clock_speed   (                         ),
    .inband_duplex_status (                         )
);

tx_client_fifo #
(
    .DEVICE               (DEVICE                   )
)
u6_tx_fifo
(
    .rd_clk               (tx_clk_int               ),
    .rd_sreset            (tx_reset                 ),
    .rd_enable            (tx_clk_en_int            ),
    .tx_data              (tx_data                  ),
    .tx_data_valid        (tx_valid                 ),
    .tx_ack               (tx_rdy                   ),
    .tx_collision         (tx_collision             ),
    .tx_retransmit        (tx_retransmit            ),
    .overflow             (                         ),
                            
    .wr_clk               (udp_clk                  ),
    .wr_sreset            (reset                    ),
    .wr_data              (temac_tx_data            ),
    .wr_sof_n             (temac_tx_sof             ),
    .wr_eof_n             (temac_tx_eof             ),
    .wr_src_rdy_n         (temac_tx_valid           ),
    .wr_dst_rdy_n         (temac_tx_ready           ),//temac_tx_ready
    .wr_fifo_status       (                         )
);

rx_client_fifo# 
(
    .DEVICE               (DEVICE                   )
)                           
u7_rx_fifo                  
(                           
    .wr_clk               (rx_clk_int               ),
    .wr_enable            (rx_clk_en_int            ),
    .wr_sreset            (rx_reset                 ),
    .rx_data              (rx_data                  ),
    .rx_data_valid        (rx_valid                 ),
    .rx_good_frame        (rx_correct_frame         ),
    .rx_bad_frame         (rx_error_frame           ),
    .overflow             (                         ),
    .rd_clk               (udp_clk                  ),
    .rd_sreset            (reset                    ),
    .rd_data_out          (temac_rx_data            ),//output reg [7:0] rd_data_out,
    .rd_sof_n             (temac_rx_sof             ),//output reg       rd_sof_n,
    .rd_eof_n             (temac_rx_eof             ),//output           rd_eof_n,
    .rd_src_rdy_n         (temac_rx_valid           ),//output reg       rd_src_rdy_n,
    .rd_dst_rdy_n         (temac_rx_ready           ),//input            rd_dst_rdy_n,
    .rx_fifo_status       (                         )
);



endmodule