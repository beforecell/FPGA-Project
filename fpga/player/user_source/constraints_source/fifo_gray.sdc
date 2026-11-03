# Source Gray Q -> first synchronizer D only; no RAM or second stage cut.
# Faster period wr100/mem31.25=10ns; mem31.25/video25=32ns; margin0.3ns.
set_max_delay -datapath_only -from [get_regs {mem_ports/write_fifo/wgray[*]}] -to [get_regs {mem_ports/write_fifo/wgray_r1[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {mem_ports/write_fifo/rgray[*]}] -to [get_regs {mem_ports/write_fifo/rgray_w1[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {mem_ports/current_fifo/wgray[*] mem_ports/history_fifo/wgray[*]}] -to [get_regs {mem_ports/current_fifo/wgray_r1[*] mem_ports/history_fifo/wgray_r1[*]}] 31.7
set_max_delay -datapath_only -from [get_regs {mem_ports/current_fifo/rgray[*] mem_ports/history_fifo/rgray[*]}] -to [get_regs {mem_ports/current_fifo/rgray_w1[*] mem_ports/history_fifo/rgray_w1[*]}] 31.7

set_max_delay -datapath_only -from [get_regs {pcm_fifo/wg[*]}] -to [get_regs {pcm_fifo/w1[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {pcm_fifo/rg[*]}] -to [get_regs {pcm_fifo/r1[*]}] 19.7
