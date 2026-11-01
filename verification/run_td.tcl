# Run from src/td_project, matching the original SDRAM include path.
import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj
elaborate -top top
read_adc ../user_source/constraints_source/pin.adc
read_sdc ../user_source/constraints_source/timing.sdc
read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/ip/afifo_32_16_256.tcl
read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/ip/afifo_16_32_256.tcl
cd ../../verification/td_build
export_db lesson2_elaborate.db
insert_debugger
optimize_rtl
report_area -file lesson2_rtl.area
export_db lesson2_rtl.db
optimize_gate -packarea lesson2_gate.area
legalize_phy_inst
update_timing
report_timing_status -file lesson2_gate.ts
report_timing_summary -file lesson2_gate.timing
export_db lesson2_gate.db
place
update_timing -mode manhattan
report_timing_summary -file lesson2_place.timing
export_db lesson2_place.db
route
report_area -io_info -file lesson2_phy.area
update_timing -mode final
report_timing_status -file lesson2_phy.ts
report_timing_summary -file lesson2_pr.timing
report_timing_exception -file lesson2_exception.timing
export_db lesson2_pr.db
bitgen -bit lesson2_controls.bit
puts "LESSON2_TD_BUILD_COMPLETE"
