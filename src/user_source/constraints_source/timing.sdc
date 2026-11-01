# All clocks are concurrent; derive frequency/phase from the actual PLL.
create_clock -name clk -period 20 -waveform {0 10} [get_ports {clk}]
derive_clocks
rename_clock -name {sd_card_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {ext_mem_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {sys_pll_m0/pll_inst.clkc[1]}]
rename_clock -name {video_clk}   -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[0]}]
rename_clock -name {hdmi_5x_clk} -source [get_ports {clk}] -master_clock {clk} [get_pins {video_pll_m0/pll_inst.clkc[1]}]

# Lesson 3 bundled-data CDC routing bounds (ns).
# Payload is held until acknowledged; 3 receiver edges synchronize its token.
# Bounds are tighter than the protocol's minimum settling window. These are
# datapath checks, NOT global asynchronous/false-path exceptions.
set_max_delay -datapath_only 20 -from [get_regs {sd_card_bmp_m0/disp_buf_idx[*] sd_card_bmp_m0/commit_sequence[*]}] -to [get_regs {u_media_transition/pending_buffer[*] u_media_transition/pending_scene[*] u_media_transition/pending_sequence[*]}]
set_max_delay -datapath_only 6 -from [get_regs {u_media_present_bridge/selected_buffer[*]}] -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/read_addr_index_d0[*]}]
set_max_delay -datapath_only 20 -from [get_regs {frame_read_write_m0/frame_fifo_read_m0/read_adopt_buffer[*]}] -to [get_regs {u_media_present_bridge/*}]
set_max_delay -datapath_only 6 -from [get_regs {sd_card_bmp_m0/commit_toggle}] -to [get_regs {u_media_transition/token_sync[0]}]
set_max_delay -datapath_only 6 -from [get_regs {u_media_present_bridge/adoption_ack}] -to [get_regs {sd_card_bmp_m0/present_sync[0]}]
set_max_delay -datapath_only 6 -from [get_regs {u_media_present_bridge/memory_request}] -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/read_req_d0}]
set_max_delay -datapath_only 6 -from [get_clocks {ext_mem_clk}] -to [get_regs {u_media_present_bridge/ack_sync[0]}]
set_max_delay -datapath_only 6 -from [get_regs {frame_read_write_m0/frame_fifo_read_m0/read_adopt_toggle}] -to [get_regs {u_media_present_bridge/adopt_sync[0]}]
set_max_delay -datapath_only 6 -from [get_regs {sd_card_bmp_m0/display_valid}] -to [get_regs {u_media_transition/valid_sync[0]}]

# FIFO IP asynchronously asserts and locally synchronizes reset release.
# Only the asynchronous reset source paths into the two reset-synchronizer
# flops are excepted. The stage0 -> stage1 D path and downstream recovery
# paths are still timed. No SDRAM data, address, or broad clock cut is used.
set_false_path -from [get_regs {u_mem_reset/release_pipe[2] frame_read_write_m0/frame_fifo_read_m0/fifo_aclr}] -to [get_regs {frame_read_write_m0/read_buf/asy_r_rst0 frame_read_write_m0/read_buf/asy_r_rst1}]
set_false_path -from [get_regs {u_mem_reset/release_pipe[2] frame_read_write_m0/frame_fifo_write_m0/fifo_aclr}] -to [get_regs {frame_read_write_m0/write_buf/asy_w_rst0 frame_read_write_m0/write_buf/asy_w_rst1}]
# Held requests and completion tokens cross through explicit three-stage synchronizers.
set_max_delay -datapath_only 6 -from [get_regs {sd_card_bmp_m0/write_req}] -to [get_regs {frame_read_write_m0/frame_fifo_write_m0/write_req_d0}]
set_max_delay -datapath_only 6 -from [get_regs {sd_card_bmp_m0/write_abort}] -to [get_regs {frame_read_write_m0/frame_fifo_write_m0/abort_sync[0]}]
set_max_delay -datapath_only 6 -from [get_regs {frame_read_write_m0/frame_fifo_write_m0/write_req_ack}] -to [get_regs {sd_card_bmp_m0/ack_sync[0]}]
set_max_delay -datapath_only 6 -from [get_regs {frame_read_write_m0/frame_fifo_write_m0/write_abort_ack}] -to [get_regs {sd_card_bmp_m0/abort_sync[0]}]
set_max_delay -datapath_only 6 -from [get_regs {frame_write_toggle_mem}] -to [get_regs {sd_card_bmp_m0/finish_sync[0]}]

# Only first-stage asynchronous inputs; synchronizer stage-to-stage paths remain timed.
# uart_rx feeds ONLY synchronizer stage 0, which may pack into the IO register.
# A path starting at the port ends at that first register; internal stages stay timed.
set_false_path -from [get_ports {uart_rx}]
set_max_delay -datapath_only 6 -from [get_clocks {video_clk}] -to [get_regs {sd_card_bmp_m0/busy_sync[0]}]

# Gallery travels with the held presentation descriptor.
set_max_delay -datapath_only 20 -from [get_regs {sd_card_bmp_m0/view_gallery}] -to [get_regs {u_media_transition/pending_gallery}]
set_max_delay -datapath_only 6 -from [get_regs {u_media_present_bridge/selected_gallery}] -to [get_regs {frame_read_write_m0/frame_fifo_read_m0/gallery_d0}]
set_max_delay -datapath_only 20 -from [get_regs {frame_read_write_m0/frame_fifo_read_m0/read_adopt_gallery}] -to [get_regs {u_media_present_bridge/*}]
# Source-registered Gray buses arrive within one source-clock period.
set_max_delay -datapath_only 6 -from [get_regs {u_wav_scene_player/fifo/wr_gray[*]}] -to [get_regs {u_wav_scene_player/fifo/wr_gray_r0[*]}]
set_max_delay -datapath_only 20 -from [get_regs {u_wav_scene_player/fifo/rd_gray[*]}] -to [get_regs {u_wav_scene_player/fifo/rd_gray_w0[*]}]
set_max_delay -datapath_only 6 -from [get_regs {u_wav_scene_player/scene_token}] -to [get_regs {u_wav_scene_player/token_sync[0]}]
set_max_delay -datapath_only 6 -from [get_regs {u_wav_scene_player/run_registered}] -to [get_regs {u_wav_scene_player/run_sync[0]}]
set_max_delay -datapath_only 6 -from [get_regs {u_wav_scene_player/quiet_registered}] -to [get_regs {u_wav_scene_player/quiet_sync[0]}]
set_max_delay -datapath_only 20 -from [get_regs {u_media_present_bridge/scene_id[*]}] -to [get_regs {u_wav_scene_player/wanted_scene[*]}]
# Playback completion is tagged with the same held scene sequence. SD-domain
# autoplay compares the tag before starting its post-audio dwell timer.
set_max_delay -datapath_only 20 -from [get_regs {u_media_present_bridge/scene_sequence[*]}] -to [get_regs {u_wav_scene_player/playback_sequence[*]}]
set_max_delay -datapath_only 6 -from [get_regs {u_wav_scene_player/stream_enable u_wav_scene_player/stream_finished u_wav_scene_player/fifo_reset}] -to [get_regs {u_wav_scene_player/enable_sync[0] u_wav_scene_player/end_sync[0] u_wav_scene_player/flush_sync[0]}]
# Local menu command: field/direction remain held through a three-stage token.
set_max_delay -datapath_only 6 -from [get_regs {sd_card_bmp_m0/local_request}] -to [get_regs {u_scene_caption_overlay/local_sync[0]}]
set_max_delay -datapath_only 20 -from [get_regs {sd_card_bmp_m0/local_field[*] sd_card_bmp_m0/local_decrease}] -to [get_regs {u_scene_caption_overlay/adjust_field[*] u_scene_caption_overlay/adjust_down}]

# Confirmed missing/invalid WAV fallback flag, SD -> PCM first stage only.
set_max_delay -datapath_only 6 -from [get_regs {u_wav_scene_player/fallback_allowed}] -to [get_regs {u_wav_scene_player/fallback_sync[0]}]
