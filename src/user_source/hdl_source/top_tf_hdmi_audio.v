
module top(
    input                       clk,
    input                       rst_n,
    input                       key1,           // 短按下一张；长按调周期
    input                       uart_rx,
    output                      uart_tx,
    input                       key2,           // 短按轮播开关；长按上一张

    output [5:0]                seg_sel,
    output [7:0]                seg_data,

    // HDMI TMDS
    output                      HDMI_CLK_P,
    output                      HDMI_D2_P,
    output                      HDMI_D1_P,
    output                      HDMI_D0_P,

    // HDMI DDC
    output                      HDMI_DDC_SCL,
    inout                       HDMI_DDC_SDA,

    // TF card SPI
    output                      sd_ncs,
    output                      sd_dclk,
    output                      sd_mosi,
    input                       sd_miso
);

// 0: image-associated notes; 1: fixed 1 kHz sine once HDMI video locks.
parameter AUDIO_TEST_MODE = 0;
parameter MEM_DATA_BITS = 32;
parameter ADDR_BITS     = 21;
parameter BUSRT_BITS    = 10;
parameter FRAME_PIXELS  = 24'd307200;   // 640*480
parameter BUF0_ADDR     = 24'd0;
parameter BUF1_ADDR     = FRAME_PIXELS;
parameter BUF2_ADDR     = FRAME_PIXELS * 2;
parameter BUF3_ADDR     = FRAME_PIXELS * 3;

wire rst_all;
wire Sdr_init_done;
wire Sdr_init_ref_vld;
wire Sdr_busy;

wire sd_card_clk;
wire ext_mem_clk;
wire ext_mem_clk_sft;
wire video_clk;
wire hdmi_5x_clk;

wire hs;
wire vs;
wire de;

wire [23:0] vout_data_raw;
wire [23:0] vout_data;
wire        display_valid;

wire [3:0]  state_code;
wire [2:0] picture_number, picture_count;
wire auto_enabled, player_loading, scan_complete;
wire [3:0] period_seconds;
wire [7:0] status_digit0, status_digit1, status_digit2;
wire [7:0] status_digit3, status_digit4, status_digit5;

wire        video_read_req;
wire        video_read_req_ack;
wire        video_read_en;
wire [31:0] video_read_data;

wire        sd_card_write_en;
wire sd_card_write_capacity;
reg sd_card_write_ready;
wire [31:0] sd_card_write_data;
wire sd_card_write_abort, sd_card_write_abort_ack;
(* keep="true" *) wire [3:0] cache_ready,cache_failed,cache_found;
(* keep="true" *) wire [7:0] storage_error;
(* keep="true" *) wire [15:0] sd_retry_count;
(* keep="true" *) wire [31:0] first_frame_ms,all_cached_ms,last_error_lba;
wire        sd_card_write_req;
wire        sd_card_write_req_ack;
wire        frame_write_finish;
reg         frame_write_toggle_mem;

wire [1:0]  write_buf_idx;
wire [1:0]  disp_buf_idx;
wire source_gallery,fx_gallery,selected_gallery,scene_gallery,read_adopt_gallery;
wire [1:0] gallery_focus;
wire [3:0] audio_found_mask;
wire wav_file_available,wav_file_request,wav_file_cancel,wav_file_start,wav_file_busy,wav_file_done;
wire [1:0] wav_file_id;
wire [31:0] wav_file_size;
wire [7:0] wav_file_error,wav_byte_data,wav_error;
wire wav_byte_valid,wav_byte_ready,wav_active;
(* keep="true" *) wire [15:0] wav_underflows;
wire tone_valid;wire [23:0] tone_left,tone_right;
wire [23:0] gallery_rgb;
wire menu_active,local_request,local_decrease,wave_enabled,caption_enabled;
wire [2:0] menu_field,local_field;
wire [1:0] wave_mode;
wire [7:0] image_audio_map,audio_playback_sequence;
wire audio_playback_complete,wav_finished,audio_waiting;
wire App_ref_req;
wire [8:0] display_contrast;
wire contrast_de,contrast_vs,plot_de,plot_vs;
wire [23:0] contrast_rgb,plot_rgb,settings_rgb;

wire App_rd_en;
wire [ADDR_BITS-1:0] App_rd_addr;
wire Sdr_rd_en;
wire [MEM_DATA_BITS-1:0] Sdr_rd_dout;
wire App_wr_en;
wire [ADDR_BITS-1:0] App_wr_addr;
wire [MEM_DATA_BITS-1:0] App_wr_din;
wire [3:0] App_wr_dm;

wire hs_0;
wire vs_0;
wire de_0;

// HDMI 1.4b 音频发射相关
wire video_reset, sd_reset, mem_reset, audio_sample_enable, hdmi_video_locked;
wire sys_pll_lock, video_pll_lock;
// PCM cadence and HDMI ACR both use video_clk; no separate audio PLL is needed.
wire reset_request = ~rst_n | ~sys_pll_lock | ~video_pll_lock;
wire commit_toggle, present_ack_toggle, present_pending;
wire transition_busy,transition_fault,fx_toggle,fx_valid;
wire [1:0] fx_buffer,fx_scene;wire [7:0] fx_sequence;
wire [8:0] transition_gain,display_brightness,user_volume;
wire status_enable,caption_de,caption_vs,display_de,display_vs;
wire [23:0] caption_rgb,scaled_rgb,status_rgb;
reg raw_vs_old;
wire display_frame_tick=vs && !raw_vs_old;
always @(posedge video_clk or posedge video_reset)
 if(video_reset)raw_vs_old<=0;else raw_vs_old<=vs;
reg [17:0] audio_volume_product;
always @(posedge video_clk or posedge video_reset)
 if(video_reset)audio_volume_product<=0;else audio_volume_product<=user_volume*transition_gain;
wire [7:0] commit_sequence;
wire [1:0] commit_scene, selected_read_buffer, read_adopt_buffer;
wire memory_read_req, memory_read_ack, read_adopt_toggle, read_fifo_empty;
wire frame_pixels_valid, scene_event, scene_valid;
reg scene_present_toggle,visible_scene_seen;reg [7:0] visible_sequence;
(* keep="true" *) wire [1:0] audio_scene_id, audio_active_scene;
(* keep="true" *) wire [7:0] audio_scene_sequence;
(* keep="true" *) wire [8:0] audio_envelope_gain;
(* keep="true" *) wire signed [15:0] pcm_probe;
(* keep="true" *) wire pcm_probe_valid;
(* keep="true" *) wire [31:0] audio_sample_count;
(* keep="true" *) wire [15:0] audio_deadline_misses;
(* keep="true" *) wire [15:0] media_late_count, media_underflow_count, media_protocol_count;
wire audio_cadence_fault;
wire media_audio_fault = audio_cadence_fault || (audio_deadline_misses!=0) || (media_late_count!=0) ||
                        (media_underflow_count!=0) || (media_protocol_count!=0) || transition_fault;
(* async_reg="true" *) reg [2:0] media_fault_sync;
always @(posedge sd_card_clk or posedge sd_reset)
    if(sd_reset) media_fault_sync<=0;
    else media_fault_sync<={media_fault_sync[1:0],media_audio_fault};
wire        audio_valid;
wire [23:0] audio_left_data;
wire [23:0] audio_right_data;
wire        acr_valid;
wire [19:0] acr_cts;
wire [19:0] acr_n;

wire        axis_s_user;
wire        axis_s_valid;
wire        axis_s_last;
wire [23:0] axis_s_data;
wire        axis_s_ready;

wire        edid_trig;
wire        edid_valid;
wire [7:0]  edid_data;

wire [9:0]  tmds_ch0_data;
wire [9:0]  tmds_ch1_data;
wire [9:0]  tmds_ch2_data;
wire [9:0]  tmds_clk_data;

always @(posedge video_clk or posedge video_reset)
 if(video_reset)begin scene_present_toggle<=0;visible_scene_seen<=0;visible_sequence<=0;end
 else if(axis_s_user && axis_s_valid && axis_s_ready && scene_valid && frame_pixels_valid && transition_gain!=0 &&
         (!visible_scene_seen || visible_sequence!=audio_scene_sequence))begin
  scene_present_toggle<=~scene_present_toggle;visible_scene_seen<=1;visible_sequence<=audio_scene_sequence;
 end

// Wait for all PLL locks and 20 ms startup hold, then release per domain.
reset_startup_guard u_startup_reset(.clk(clk),.arst(reset_request),.rst(rst_all));
reset_release_sync u_sd_reset(.clk(sd_card_clk),.arst(rst_all),.rst(sd_reset));
reset_release_sync u_mem_reset(.clk(ext_mem_clk),.arst(rst_all),.rst(mem_reset));
// Break FIFO occupancy subtraction -> decoder state/data enables. The FIFO
// stops granting capacity at 384/512 words, leaving 128 words for flag and
// pipeline latency; this register adds at most one outstanding pixel.
always @(posedge sd_card_clk or posedge sd_reset)
 if(sd_reset)sd_card_write_ready<=0;
 else sd_card_write_ready<=sd_card_write_capacity;

// 保持你原来的 TF / SDRAM / video 时钟
sys_pll sys_pll_m0(
    .refclk     (clk),
    .clk0_out   (sd_card_clk),
    .clk1_out   (ext_mem_clk),
    .clk2_out   (ext_mem_clk_sft),
    .locked     (sys_pll_lock),
    .reset      (~rst_n)
);

video_pll video_pll_m0(
    .refclk     (clk),
    .clk0_out   (video_clk),
    .clk1_out   (hdmi_5x_clk),
    .locked     (video_pll_lock),
    .reset      (~rst_n)
);

// mem_clk 域把 write_finish 单拍转成 toggle，供 sd_card_clk 域可靠同步
always @(posedge ext_mem_clk or posedge mem_reset) begin
    if (mem_reset)
        frame_write_toggle_mem <= 1'b0;
    else if (frame_write_finish)
        frame_write_toggle_mem <= ~frame_write_toggle_mem;
end

// ===================== FAT32 首图启动与四帧缓存 =====================
sd_card_bmp #(
    .CLK_FREQ_HZ       (100_000_000)
) sd_card_bmp_m0(
    .clk               (sd_card_clk),
    .rst               (sd_reset),
    .key_next          (key1),
    .key_auto          (key2),
    .state_code        (state_code),
    .bmp_width         (16'd640),
    .bmp_height        (16'd480),
    .display_valid     (display_valid),
    .picture_number    (picture_number),
    .picture_count     (picture_count),
    .auto_enabled      (auto_enabled),
    .period_seconds    (period_seconds),
    .loading           (player_loading),
    .scan_complete     (scan_complete),

    .write_finish_toggle(frame_write_toggle_mem),
    .write_buf_idx     (write_buf_idx),
    .disp_buf_idx      (disp_buf_idx),
    .transition_busy(transition_busy),
    .scene_present_toggle(scene_present_toggle),
    .present_ack_toggle(present_ack_toggle),
    .commit_toggle     (commit_toggle),
    .commit_sequence   (commit_sequence),
    .commit_scene      (commit_scene),
    .present_pending   (present_pending),

    .write_abort       (sd_card_write_abort),
    .write_abort_ack   (sd_card_write_abort_ack),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_en          (sd_card_write_en),
    .write_ready(sd_card_write_ready),
    .write_data        (sd_card_write_data),
    .ready_mask(cache_ready),.failed_mask(cache_failed),.found_mask(cache_found),
    .last_error(storage_error),.sd_retry_count(sd_retry_count),
    .first_frame_ms(first_frame_ms),.all_cached_ms(all_cached_ms),.last_error_lba(last_error_lba),
    .view_gallery(source_gallery),.gallery_focus(gallery_focus),
    .menu_active(menu_active),.menu_field(menu_field),.local_request(local_request),.local_field(local_field),.local_decrease(local_decrease),
    .image_audio_map(image_audio_map),.audio_playback_complete(audio_playback_complete),.audio_playback_sequence(audio_playback_sequence),
    .audio_found_mask(audio_found_mask),.audio_available(wav_file_available),
    .audio_request(wav_file_request),.audio_id(wav_file_id),.audio_cancel(wav_file_cancel),
    .audio_start(wav_file_start),.audio_busy(wav_file_busy),.audio_done(wav_file_done),
    .audio_size(wav_file_size),.audio_error(wav_file_error),
    .audio_byte_valid(wav_byte_valid),.audio_byte_data(wav_byte_data),.audio_byte_ready(wav_byte_ready),
    .SD_nCS            (sd_ncs),
    .SD_DCLK           (sd_dclk),
    .SD_MOSI           (sd_mosi),
    .SD_MISO           (sd_miso)
);

// Keep status encoding and six-digit scan in the controller clock domain.
player_status_display u_player_status_display(
    .display_valid(display_valid), .scan_complete(scan_complete),
    .loading(player_loading), .picture_number(picture_number),
    .picture_count(picture_count), .auto_enabled(auto_enabled),
    .period_seconds(period_seconds), .source_state(state_code),
    .digit0(status_digit0), .digit1(status_digit1), .digit2(status_digit2),
    .digit3(status_digit3), .digit4(status_digit4), .digit5(status_digit5)
);

seg_scan #(.CLK_FREQ(100_000_000)) seg_scan_m0(
    .clk(sd_card_clk), .rst_n(~sd_reset),
    .seg_sel(seg_sel), .seg_data(seg_data),
    .seg_data_0(status_digit0), .seg_data_1(status_digit1),
    .seg_data_2(status_digit2), .seg_data_3(status_digit3),
    .seg_data_4(status_digit4), .seg_data_5({status_digit5[7] & ~media_fault_sync[2],status_digit5[6:0]})
);

// ===================== 原图像时序与帧缓存 =====================
video_timing_data video_timing_data_m0(
    .video_clk         (video_clk),
    .rst               (video_reset),
    .read_req          (video_read_req),
    .read_req_ack      (video_read_req_ack),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0)
);

video_delay video_delay_m0(
    .video_clk         (video_clk),
    .rst               (video_reset),
    .read_en           (video_read_en),
    .read_data         (video_read_data[31:8]),
    .hs                (hs_0),
    .vs                (vs_0),
    .de                (de_0),
    .hs_r              (hs),
    .vs_r              (vs),
    .de_r              (de),
    .vout_data         (vout_data_raw)
);

// 首图提交前黑屏；提交后一直显示当前显示缓冲区内容
wire [23:0] image_rgb = frame_pixels_valid ? vout_data_raw : 24'd0;
video_rgb_contrast u_video_rgb_contrast(
 .clk(video_clk),.rst(video_reset),.de(de),.vs(vs),.rgb(image_rgb),.contrast(display_contrast),
 .de_out(contrast_de),.vs_out(contrast_vs),.rgb_out(contrast_rgb));
gallery_overlay u_gallery_overlay(
 .clk(video_clk),.rst(video_reset),.de(contrast_de),.vs(contrast_vs),.rgb(contrast_rgb),
 .enable(selected_gallery),.focus(gallery_focus),.ready_mask(cache_ready),.failed_mask(cache_failed),.out_rgb(gallery_rgb));
scene_caption_overlay u_scene_caption_overlay(
 .clk(video_clk),.rst(video_reset),.de(contrast_de),.vs(contrast_vs),.rgb(gallery_rgb),
 .scene_valid(scene_valid && !selected_gallery),.scene_id(audio_scene_id),.uart_rx(uart_rx),.uart_tx(uart_tx),
 .scene_theme_map(image_audio_map),
 .de_out(caption_de),.vs_out(caption_vs),.rgb_out(caption_rgb),
 .brightness(display_brightness),.volume(user_volume),.status_enable(status_enable),
 .local_request(local_request),.local_field(local_field),.local_decrease(local_decrease),
 .contrast(display_contrast),.wave_enable(wave_enabled),.wave_mode(wave_mode),.caption_enable(caption_enabled));
video_rgb_gain u_video_rgb_gain(
 .clk(video_clk),.rst(video_reset),.de(caption_de),.vs(caption_vs),.rgb(caption_rgb),
 .fade_gain(transition_gain),.brightness(display_brightness),
 .de_out(display_de),.vs_out(display_vs),.rgb_out(scaled_rgb));
pcm_wave_overlay u_pcm_wave_overlay(
 .clk(video_clk),.rst(video_reset),.de(display_de),.vs(display_vs),.rgb(scaled_rgb),
 .enable(wave_enabled && !selected_gallery),.history_mode(wave_mode==2),.clear_history(scene_event),.sample_valid(pcm_probe_valid),.sample(pcm_probe),
 .de_out(plot_de),.vs_out(plot_vs),.rgb_out(plot_rgb));
local_settings_overlay u_local_settings_overlay(
 .clk(video_clk),.rst(video_reset),.de(plot_de),.vs(plot_vs),.rgb((status_enable && !selected_gallery)?status_rgb:plot_rgb),
 .menu_active(menu_active),.menu_field(menu_field),.brightness(display_brightness),.contrast(display_contrast),
 .volume(user_volume),.wave_mode(wave_mode),.caption_enable(caption_enabled),.out_rgb(settings_rgb));
player_osd u_player_osd(.clk(video_clk),.rst(video_reset),.de(plot_de),.vs(plot_vs),.rgb(plot_rgb),
 .display_valid(scene_valid),.scan_complete(scan_complete),.auto_enabled(auto_enabled),
 .scene(audio_scene_id),.period_seconds(period_seconds),.ready_mask(cache_ready),
 .brightness(display_brightness),.volume(user_volume),
 .failed_mask(cache_failed),.found_mask(cache_found),
 .wav_active(wav_active),.wav_error(wav_error),.wav_underflow(wav_underflows!=0),
 .wave_enable(wave_enabled),.history_mode(wave_mode==2),.wav_finished(wav_finished),.audio_waiting(audio_waiting),
 .error_code(storage_error!=0?storage_error:(transition_fault?8'he1:8'd0)),.out_rgb(status_rgb));
assign vout_data=settings_rgb;

frame_read_write #(
    .WRITE_V_FLIP     (1),
    .FRAME_WIDTH      (640),
    .FRAME_HEIGHT     (480)
) frame_read_write_m0(
    .App_ref_req       (App_ref_req),
    .mem_clk           (ext_mem_clk),
    .rst               (mem_reset),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),

    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout),

    .read_clk          (video_clk),
    .read_req          (memory_read_req),
    .read_req_ack      (memory_read_ack),
    .read_finish       (),
    .read_adopt_toggle (read_adopt_toggle),
    .read_adopt_buffer (read_adopt_buffer),
    .read_gallery(selected_gallery),.read_adopt_gallery(read_adopt_gallery),
    .read_fifo_empty   (read_fifo_empty),
    .read_addr_0       (BUF0_ADDR[ADDR_BITS-1:0]),
    .read_addr_1       (BUF1_ADDR[ADDR_BITS-1:0]),
    .read_addr_2       (BUF2_ADDR[ADDR_BITS-1:0]),
    .read_addr_3       (BUF3_ADDR[ADDR_BITS-1:0]),
    .read_addr_index   (selected_read_buffer),
    .read_len          (FRAME_PIXELS[ADDR_BITS-1:0]),
    .read_en           (video_read_en && frame_pixels_valid && !read_fifo_empty),
    .read_data         (video_read_data),

    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_din        (App_wr_din),
    .App_wr_dm         (App_wr_dm),

    .write_clk         (sd_card_clk),
    .write_abort       (sd_card_write_abort),
    .write_abort_ack   (sd_card_write_abort_ack),
    .write_req         (sd_card_write_req),
    .write_req_ack     (sd_card_write_req_ack),
    .write_finish      (frame_write_finish),
    .write_addr_0      (BUF0_ADDR[ADDR_BITS-1:0]),
    .write_addr_1      (BUF1_ADDR[ADDR_BITS-1:0]),
    .write_addr_2      (BUF2_ADDR[ADDR_BITS-1:0]),
    .write_addr_3      (BUF3_ADDR[ADDR_BITS-1:0]),
    .write_addr_index  (write_buf_idx),
    .write_len         (FRAME_PIXELS[ADDR_BITS-1:0]),
    .write_en          (sd_card_write_en),
    .write_ready(sd_card_write_capacity),
    .write_data        (sd_card_write_data)
);

sdram U3(
    .App_ref_req       (App_ref_req),
    .Clk               (ext_mem_clk),
    .Clk_sft           (ext_mem_clk_sft),
    .Rst               (mem_reset),
    .Sdr_init_done     (Sdr_init_done),
    .Sdr_init_ref_vld  (Sdr_init_ref_vld),
    .Sdr_busy          (Sdr_busy),
    .App_wr_en         (App_wr_en),
    .App_wr_addr       (App_wr_addr),
    .App_wr_dm         (App_wr_dm),
    .App_wr_din        (App_wr_din),
    .App_rd_en         (App_rd_en),
    .App_rd_addr       (App_rd_addr),
    .Sdr_rd_en         (Sdr_rd_en),
    .Sdr_rd_dout       (Sdr_rd_dout)
);


// ===================== PCM and frame ownership =====================
reset_release_sync u_video_reset(.clk(video_clk),.arst(rst_all),.rst(video_reset));
media_transition u_media_transition(
 .clk(video_clk),.rst(video_reset),.frame_tick(display_frame_tick),
 .source_toggle(commit_toggle),.source_valid(display_valid),.source_buffer(disp_buf_idx),.source_gallery(source_gallery),
 .source_scene(commit_scene),.source_sequence(commit_sequence),
 .presented_valid(scene_valid),.presented_sequence(audio_scene_sequence),
 .commit_toggle(fx_toggle),.commit_valid(fx_valid),.commit_buffer(fx_buffer),
 .commit_scene(fx_scene),.commit_sequence(fx_sequence),.commit_gallery(fx_gallery),.gain(transition_gain),
 .busy(transition_busy),.timeout_fault(transition_fault));
media_present_bridge u_media_present_bridge(
    .clk(video_clk),.rst(video_reset),
    .commit_toggle(fx_toggle),.source_valid(fx_valid),.commit_gallery(fx_gallery),
    .commit_buffer(fx_buffer),.commit_scene(fx_scene),.commit_sequence(fx_sequence),
    .adoption_ack(present_ack_toggle),
    .frame_request(video_read_req),.frame_request_ack(video_read_req_ack),
    .memory_request(memory_read_req),.memory_ack(memory_read_ack),
    .memory_adopt_toggle(read_adopt_toggle),.memory_adopt_buffer(read_adopt_buffer),
    .selected_buffer(selected_read_buffer),.selected_gallery(selected_gallery),.scene_gallery(scene_gallery),
    .memory_adopt_gallery(read_adopt_gallery),
    .pixel_read(video_read_en),.fifo_empty(read_fifo_empty),
    .axis_sof(axis_s_user),.axis_valid(axis_s_valid),.axis_ready(axis_s_ready),
    .video_locked(hdmi_video_locked),.pixels_valid(frame_pixels_valid),
    .scene_event(scene_event),.scene_valid(scene_valid),.scene_id(audio_scene_id),
    .scene_sequence(audio_scene_sequence),.late_count(media_late_count),
    .underflow_count(media_underflow_count),.protocol_count(media_protocol_count)
);
audio_cadence_monitor u_audio_cadence_monitor(
    .clk(video_clk),.rst(video_reset),.frame_start(axis_s_valid && axis_s_user),
    .sample_count(audio_sample_count),.cadence_fault(audio_cadence_fault)
);
audio_sample_tick u_audio_sample_tick(
    .clk(video_clk),.rst(video_reset),.sample_tick(audio_sample_enable)
);
pcm_scene_audio #(.TEST_MODE(AUDIO_TEST_MODE), .PCM_SHIFT(3),
    .STARTUP_STEP_SAMPLES(96), .SCENE_FADE_STEP_SAMPLES(24)) u_pcm_scene_audio(
    .clk(video_clk),.rst(video_reset),.sample_tick(audio_sample_enable),
    .run_enable(AUDIO_TEST_MODE!=0 ? hdmi_video_locked : (scene_valid && !scene_gallery)),
    .scene_event(AUDIO_TEST_MODE!=0 ? 1'b0 : scene_event),
    .scene_id(audio_scene_id),.volume_gain(audio_volume_product[16:8]),
    .audio_valid(tone_valid),.audio_left(tone_left),.audio_right(tone_right),
    .pcm_probe(),.pcm_probe_valid(),
    .active_scene(audio_active_scene),.envelope_gain(audio_envelope_gain),
    .sample_count(audio_sample_count),.deadline_miss_count(audio_deadline_misses)
);

wav_scene_player #(.FORCE_TONE(AUDIO_TEST_MODE!=0)) u_wav_scene_player(
 .sd_clk(sd_card_clk),.sd_rst(sd_reset),.pcm_clk(video_clk),.pcm_rst(video_reset),.sample_tick(audio_sample_enable),
 .run_enable(AUDIO_TEST_MODE==0 && scene_valid && !scene_gallery),.scene_event(scene_event),.scene_id(audio_scene_id),
 .scene_sequence(audio_scene_sequence),.image_audio_map(image_audio_map),
 .volume_gain(audio_volume_product[16:8]),.tone_valid(tone_valid),.tone_left(tone_left),
 .audio_valid(audio_valid),.audio_left(audio_left_data),.wav_active(wav_active),.underflow_count(wav_underflows),
 .wav_finished(wav_finished),.audio_waiting(audio_waiting),.playback_complete(audio_playback_complete),.playback_sequence(audio_playback_sequence),
 .found_mask(audio_found_mask),.file_available(wav_file_available),.file_request(wav_file_request),.file_id(wav_file_id),
 .file_cancel(wav_file_cancel),.file_start(wav_file_start),.file_busy(wav_file_busy),.file_done(wav_file_done),
 .file_size(wav_file_size),.file_error(wav_file_error),.byte_valid(wav_byte_valid),.byte_data(wav_byte_data),
 .byte_ready(wav_byte_ready),.last_error(wav_error));
assign audio_right_data=audio_left_data;
assign pcm_probe=$signed(audio_left_data[23:8]);
assign pcm_probe_valid=audio_valid;

audio_arc_calculate #(
    .ACR_N         (6144)
) u_audio_arc_calculate (
    .I_clk         (video_clk),
    .I_rst         (video_reset),
    .I_audio_valid (audio_valid),
    .O_acr_valid   (acr_valid),
    .O_acr_cts     (acr_cts),
    .O_acr_n       (acr_n)
);

// ===================== RGB/DE 转 AXIS 视频 =====================
video_rgb_to_axis_640x480 u_video_rgb_to_axis_640x480(
    .I_clk         (video_clk),
    .I_rst         (video_reset),
    .I_vs          (plot_vs),
    .I_de          (plot_de),
    .I_rgb         (vout_data),
    .O_video_user  (axis_s_user),
    .O_video_valid (axis_s_valid),
    .O_video_last  (axis_s_last),
    .O_video_data  (axis_s_data)
);

// 上电后自动打一拍，触发一次 EDID 读取
startup_pulse #(
    .CNT_MAX(20'd100000)
) u_startup_pulse (
    .I_clk   (video_clk),
    .I_rst   (video_reset),
    .O_pulse (edid_trig)
);

// ===================== 带音频的 HDMI 1.4b 发射 =====================
hdmi_1_4b_transmitter_core_wrapper #(
    .DEVICE                 ( "EG"       ),
    .HTOTAL                 ( 800        ),
    .HSA                    ( 96         ),
    .HFP                    ( 16         ),
    .HBP                    ( 48         ),
    .HACTIVE                ( 640        ),
    .VTOTAL                 ( 525        ),
    .VSA                    ( 2          ),
    .VFP                    ( 10         ),
    .VBP                    ( 33         ),
    .VACTIVE                ( 480        ),
    .VIDEO_VIC              ( 1          ),
    .VIDEO_TPG              ( "Disable"  ),
    .VIDEO_FORMAT           ( "RGB"      ),
    .AUDIO_SAMPLE_RATE      ( "48K"      ),
    .IIC_SCL_DIV            ( 250        )
) u_hdmi_1_4b_transmitter_core_wrapper(
    .I_pixel_clk        (video_clk),
    .I_rst              (video_reset),
    .I_edid_read_trig   (edid_trig),
    .O_edid_read_valid  (edid_valid),
    .O_edid_read_data   (edid_data),

    .I_axis_s_user      (axis_s_user),
    .I_axis_s_valid     (axis_s_valid),
    .I_axis_s_last      (axis_s_last),
    .I_axis_s_data      (axis_s_data),
    .O_axis_s_ready     (axis_s_ready),

    .I_audio_valid      (audio_valid),
    .I_audio_left_data  (audio_left_data),
    .I_audio_right_data (audio_right_data),
    .I_acr_valid        (acr_valid),
    .I_acr_cts          (acr_cts),
    .I_acr_n            (acr_n),

    .O_video_locked     (hdmi_video_locked),
    .O_ddc_scl          (HDMI_DDC_SCL),
    .IO_ddc_sda         (HDMI_DDC_SDA),

    .O_ch0_tmds_data    (tmds_ch0_data),
    .O_ch1_tmds_data    (tmds_ch1_data),
    .O_ch2_tmds_data    (tmds_ch2_data),
    .O_clk_tmds_data    (tmds_clk_data)
);

hdmi_phy_wrapper #(
    .DEVICE ( "EG" )
) u_hdmi2phy_wrapper(
    .I_pixel_clk        (video_clk),
    .I_serial_clk       (hdmi_5x_clk),
    .I_rst              (video_reset),
    .I_tmds_channel_0   (tmds_ch0_data),
    .I_tmds_channel_1   (tmds_ch1_data),
    .I_tmds_channel_2   (tmds_ch2_data),
    .I_tmds_channel_clk (tmds_clk_data),
    .O_tmds_ch0_p       (HDMI_D0_P),
    .O_tmds_ch1_p       (HDMI_D1_P),
    .O_tmds_ch2_p       (HDMI_D2_P),
    .O_tmds_clk_p       (HDMI_CLK_P)
);

endmodule
