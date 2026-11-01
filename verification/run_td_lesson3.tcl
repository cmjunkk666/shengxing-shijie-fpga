# Run from src/td_project, matching the original SDRAM include path.
import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj
elaborate -top top
read_adc ../user_source/constraints_source/pin.adc
read_sdc ../user_source/constraints_source/timing.sdc
read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/ip/afifo_32_16_256.tcl
read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/ip/afifo_16_32_256.tcl
cd ../../verification/td_build
export_db lesson3_elaborate.db
insert_debugger
optimize_rtl
report_area -file lesson3_rtl.area
export_db lesson3_rtl.db
optimize_gate -packarea lesson3_gate.area
legalize_phy_inst
update_timing
report_timing_status -file lesson3_gate.ts
report_timing_summary -file lesson3_gate.timing
export_db lesson3_gate.db
place
update_timing -mode manhattan
report_timing_summary -file lesson3_place.timing
export_db lesson3_place.db
route
report_area -io_info -file lesson3_phy.area
update_timing -mode final
report_timing_status -file lesson3_phy.ts
report_timing_summary -file lesson3_pr.timing
report_timing_exception -file lesson3_exception.timing
export_db lesson3_pr.db
# Retained diagnostic widths and new CDC endpoint lookup are part of sign-off.
set audit [open lesson3_register_audit.txt w]
foreach pattern {
    u_pcm_scene_audio/sample_count[*]
    u_pcm_scene_audio/deadline_miss_count[*]
    u_media_present_bridge/late_count[*]
    u_media_present_bridge/underflow_count[*]
    u_media_present_bridge/protocol_count[*]
    u_media_present_bridge/selected_sequence[*]
    u_media_present_bridge/scene_sequence[*]
} {
    puts $audit "$pattern : [get_regs $pattern]"
}
close $audit
bitgen -bit lesson3_scene_audio.bit
puts "LESSON3_TD_BUILD_COMPLETE"
