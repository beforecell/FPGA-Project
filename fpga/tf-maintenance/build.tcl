set root [file normalize [file dirname [info script]]]
import_device eagle_s20.db -package EG4S20BG256
cd $root/td_project
open_project $root/td_project/blackbox.al -single_run
file mkdir build
cd build
elaborate -top top
read_adc ../../user_source/constraints_source/pin.adc
read_sdc ../../user_source/constraints_source/timing.sdc
optimize_rtl
optimize_gate -packarea gate.area
legalize_phy_inst
export_db gate.db
report_area -io_info -file synthesis_area.rpt
set_param place seed 6
place
route
fix_hold
update_timing -mode final
report_area -io_info -file area.rpt
report_timing_status -file timing_status.rpt
report_timing_summary -file timing.rpt
export_db routed.db
bitgen -bit ../../blackbox.bit
exit
