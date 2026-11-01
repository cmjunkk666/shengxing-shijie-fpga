# Run from src/td_project, matching the original SDRAM include path.
import_device eagle_s20.db -package EG4S20BG256
open_project HDMI1.4b_Transmitter_v1.0.prj
set_param flow thread 4
set_param flow qor_monitor off
elaborate -top top
read_adc ../user_source/constraints_source/pin.adc
read_sdc ../user_source/constraints_source/timing.sdc
read_sdc -ip rfifo_32_32_512 ../user_source/hdl_source/ip/afifo_32_16_256.tcl
read_sdc -ip wfifo_32_32_512 ../user_source/hdl_source/ip/afifo_16_32_256.tcl
set report_dir ../../verification/td_build
export_db $report_dir/lesson3_elaborate.db
insert_debugger
optimize_rtl
report_area -file $report_dir/lesson3_rtl.area
export_db $report_dir/lesson3_rtl.db
optimize_gate -packarea $report_dir/lesson3_gate.area
legalize_phy_inst
update_timing
report_timing_status -file $report_dir/lesson3_gate.ts
report_timing_summary -file $report_dir/lesson3_gate.timing
export_db $report_dir/lesson3_gate.db
write_verilog $report_dir/display_gate.v
set_param flow enable_seed on
set_param place seed 1
set_param place effort high
set_param place opt_timing high
place
update_timing -mode manhattan
report_timing_summary -file $report_dir/lesson3_place.timing
export_db $report_dir/lesson3_place.db
set_param route post_route_opt high
route
report_area -io_info -file $report_dir/lesson3_phy.area
update_timing -mode final
report_timing_status -file $report_dir/lesson3_phy.ts
report_timing_summary -file $report_dir/lesson3_pr.timing
report_timing_exception -file $report_dir/lesson3_exception.timing
export_db $report_dir/lesson3_pr.db
# Retained diagnostic widths and new CDC endpoint lookup are part of sign-off.
set audit [open $report_dir/lesson3_register_audit.txt w]
foreach pattern {
    u_pcm_scene_audio/sample_count[*]
    u_pcm_scene_audio/deadline_miss_count[*]
    u_media_present_bridge/late_count[*]
    u_media_present_bridge/underflow_count[*]
    u_media_present_bridge/protocol_count[*]
    u_media_present_bridge/selected_sequence[*]
    u_media_present_bridge/scene_sequence[*]
    u_media_transition/pending_sequence[*]
    sd_card_bmp_m0/busy_sync[*]
} {
    puts $audit "$pattern : [get_regs $pattern]"
}
close $audit
bitgen -bit $report_dir/course_complete_hdmi_a.bit
puts "COURSE_COMPLETE_TD_BUILD_COMPLETE"

