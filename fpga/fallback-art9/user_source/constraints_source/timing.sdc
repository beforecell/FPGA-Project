create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
derive_clocks
rename_clock -name {pll_feedback100} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {raw_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {serial_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]
create_generated_clock -name mem_clk -source [get_pins {sys_pll_m0/pll_inst.clkc[1]}] -divide_by 4 [get_pins -nowarn {bb_mem_bufg.o bb_mem_bufg.clko}]
create_generated_clock -name mem_clk_sft -source [get_pins -nowarn {bb_mem_bufg.o bb_mem_bufg.clko}] -master_clock mem_clk -divide_by 1 -invert [get_pins {U3/sdram.clk}]
set_max_delay -datapath_only -to [get_regs {settings/as[0] settings/rs[0] timeline/as[0] timeline/rs[0] board_snapshot/as[0] board_snapshot/rs[0] seek_command/as[0] seek_command/rs[0] analysis_snapshot/as[0] analysis_snapshot/rs[0]}] 19.7
set_max_delay -datapath_only -from [get_regs {settings/held[*] timeline/held[*] board_snapshot/held[*] seek_command/held[*] analysis_snapshot/held[*]}] -to [get_regs {settings/dst_data[*] timeline/dst_data[*] board_snapshot/dst_data[*] seek_command/dst_data[*] analysis_snapshot/dst_data[*]}] 19.7
set_max_delay -datapath_only -to [get_regs {mem_ports/w_payload1[*] mem_ports/w_req_sync[0]}] 19.7
set_max_delay -datapath_only -to [get_regs {mem_ports/r_payload1[*] mem_ports/r_req_sync[0]}] 31.7
set_max_delay -datapath_only -to [get_regs {store/video/wa_sync[0] store/video/wd_sync[0] store/picture/ack[0] store/picture/finished[0] manager/refresh_sync[0] manager/ack_sync[0] fill_sync[0] mbusy_sync[0] cache_valid_sync[0] cue_finish_sync[0] loop_sync[0] flush_sync[0] memory_fault_sync[0] commit_sync[0]}] 19.7
set_max_delay -datapath_only -to [get_regs {cache/req_sync[0] cache/done_sync[0] cache/meta0[*]}] 19.7
# Async assertion source only, to asynchronous reset pins. Synchronizer Q->D
# and all functional data/control paths remain timed.
set_false_path -through [get_nets -hier {reset_raw/async_assert reset_sys/async_assert reset_mem/async_assert reset_video/async_assert reset_board/async_assert media_rs/async_assert media_rm/async_assert media_rv/async_assert phy/reset_serial/async_assert}]

# First photo-busy synchronizer: enforce a physical minimum route delay to
# cover related-clock insertion skew. This TIGHTENS the hold requirement; it
# does not cut the path or relax either functional clock.
if {[llength [get_regs {photo_busy_sync[0]}]] == 0} {error "Missing photo-busy first synchronizer"}
set_max_delay -datapath_only -to [get_regs {photo_busy_sync[0]}] 19.7
set_min_delay -to [get_regs {photo_busy_sync[0]}] 3.0
