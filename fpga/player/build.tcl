if {[catch {
set root [file normalize [file dirname [info script]]]
import_device eagle_s20.db -package EG4S20BG256
cd $root/td_project
open_project $root/td_project/blackbox.al -single_run
file mkdir build
file copy -force $root/rtl/alpha_twiddle.vh build/alpha_twiddle.vh
file copy -force $root/rtl/alpha_labels.vh build/alpha_labels.vh
cd build
set_param gate eram_init on
elaborate -top top
read_adc ../../user_source/constraints_source/pin.adc
read_sdc ../../user_source/constraints_source/timing.sdc
read_sdc ../../user_source/constraints_source/fifo_gray.sdc
puts "RESET_ASSERT_NETS: [get_nets -hier {reset_raw/async_assert reset_sys/async_assert reset_mem/async_assert reset_video/async_assert reset_board/async_assert media_rs/async_assert media_rm/async_assert media_rv/async_assert phy/reset_serial/async_assert}]"
set_param gate opt_area high
set_param gate pack_effort high
set_param rtl seq_syn_effort high
set_param gate add_map_lut_struct high
set_param gate map_mode area_prior
set_param gate multi_thread_mapping partition
set_param rtl resource_sharing auto
set_param rtl shifter_style shifter_reg
optimize_rtl
optimize_gate -packarea gate.area
legalize_phy_inst
export_db gate.db
report_area -io_info -file synthesis_area.rpt
set_param place seed 1
set_param place effort high
set_param place opt_timing high
place
export_db placed.db
set_param route timing on
set_param route effort routability
set_param route post_route_opt off
set_param route hold_fix_iteration 20
write_verilog placed_netlist.v
if {[catch {route} route_error]} {
 puts "INITIAL_ROUTE_REQUIRES_REPAIR: $route_error"
 export_db initial_route_failed.db
 report_route_status -drc -remove_invalid_route
 route -incremental
}
drc_check -route -verbose
report_route_status -drc
# TD's own DefaultFlow.tcl uses fix_hold after routing. Repair the actual
# routed short paths before final setup/hold reports; do not mask them.
fix_hold
update_timing -mode final
report_area -io_info -file area.rpt
report_timing_status -file timing_status.rpt
report_timing_summary -file timing.rpt
export_db routed.db
write_verilog routed_netlist.v
export_bitgen_param -file bitgen_params.txt
set h [open timing_status.rpt r];set status [read $h];close $h
if {![regexp {SWNS:\s*(-?[0-9.]+)ns} $status all setup] || ![regexp {HWNS:\s*(-?[0-9.]+)ns} $status all hold]} {error "Missing timing"}
if {$setup<0 || $hold<0} {error "Negative final timing: $status"}
bitgen -bit ../../blackbox.bit
} build_error]} {puts stderr "ALPHA_BUILD_FAILED: $build_error"; exit 1}
exit 0
