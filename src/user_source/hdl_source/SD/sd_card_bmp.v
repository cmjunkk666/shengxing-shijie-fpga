// Four immutable cache slots. Presentation and background loading are independent.
module sd_card_bmp #(
 parameter integer CLK_FREQ_HZ=100000000,DEBOUNCE_MS=20,LONG_PRESS_MS=1000,
 parameter integer INIT_DELAY_CYCLES=10000000
)(
 input wire clk,rst,key_next,key_auto,output wire [3:0] state_code,
 input wire [15:0] bmp_width,bmp_height,output reg display_valid,
 input wire write_finish_toggle,output reg [1:0] write_buf_idx,disp_buf_idx,
 output reg write_req,input wire write_req_ack,
 output reg write_abort,input wire write_abort_ack,
 output wire write_en,output wire [31:0] write_data,
 input wire write_ready,
 output wire SD_nCS,SD_DCLK,SD_MOSI,input wire SD_MISO,
 output wire [2:0] picture_number,picture_count,output reg auto_enabled,
 output wire [3:0] period_seconds,output wire loading,scan_complete,
 input wire transition_busy,input wire scene_present_toggle,input wire present_ack_toggle,output reg commit_toggle,output reg [7:0] commit_sequence,
 output wire [1:0] commit_scene,output wire present_pending,
 output reg [3:0] ready_mask,failed_mask,output wire [3:0] found_mask,
 output reg [7:0] last_error,output wire [15:0] sd_retry_count,
 output reg [31:0] first_frame_ms,all_cached_ms,
 output wire [31:0] last_error_lba,
 output reg view_gallery,output reg [1:0] gallery_focus,
 output reg menu_active,output reg [2:0] menu_field,
 output reg local_request,output reg [2:0] local_field,output reg local_decrease,
 output wire [7:0] image_audio_map,
 input wire audio_playback_complete,input wire [7:0] audio_playback_sequence,
 output wire [3:0] audio_found_mask,output wire audio_available,
 input wire audio_request,input wire [1:0] audio_id,input wire audio_cancel,
 output reg audio_start,output wire audio_busy,audio_done,
 output wire [31:0] audio_size,output wire [7:0] audio_error,
 output wire audio_byte_valid,output wire [7:0] audio_byte_data,input wire audio_byte_ready
);
 localparam BOOT=0,INIT_WAIT=1,IDLE=2,ACK_HI=3,ACK_LO=4,READ=5,DRAIN=6,ABORT_HI=7,ABORT_LO=8,FAULT=9;
 reg [3:0] load_state;
 wire next_event,prev_event,toggle_auto_event,cycle_period_event,interaction_active,gallery_event,menu_event;
 key_events #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.DEBOUNCE_MS(DEBOUNCE_MS),.LONG_PRESS_MS(LONG_PRESS_MS)) keys(
  .clk(clk),.rst(rst),.key1_n(key_next),.key2_n(key_auto),.next_event(next_event),.prev_event(prev_event),
  .toggle_auto_event(toggle_auto_event),.cycle_period_event(cycle_period_event),.gallery_event(gallery_event),.menu_event(menu_event),.interaction_active(interaction_active));
 reg init_start,fs_start,fs_reset,file_start;wire init_done,card_ready,sector_busy;
 wire [7:0] init_error,sector_error,sector_data;wire [8:0] sector_index;
 wire sector_req,sector_ready,sector_valid,sector_done;wire [31:0] sector_lba;
 sd_sector_service #(.CLK_HZ(CLK_FREQ_HZ),.INIT_DELAY_CYCLES(INIT_DELAY_CYCLES)) sectors(
  .clk(clk),.rst(rst),.init_start(init_start),.init_done(init_done),.card_ready(card_ready),.init_error(init_error),
  .req(sector_req),.lba(sector_lba),.byte_ready(sector_ready),.busy(sector_busy),.valid(sector_valid),
  .data(sector_data),.index(sector_index),.done(sector_done),.error(sector_error),
  .retry_count(sd_retry_count),.last_error_lba(last_error_lba),
  .SD_nCS(SD_nCS),.SD_DCLK(SD_DCLK),.SD_MOSI(SD_MOSI),.SD_MISO(SD_MISO));
 wire mounted,file_available,file_busy,file_done,byte_valid;wire [7:0] fs_error,file_error,byte_data;
 wire [31:0] file_size;wire decoder_cancel,decoder_byte_ready;reg cancel_file;
 reg audio_owner;reg [1:0] audio_slot;
 wire fs_file_done,fs_byte_valid;wire [7:0] fs_byte_data;
 assign file_done=fs_file_done && !audio_owner;
 assign byte_valid=fs_byte_valid && !audio_owner;
 assign byte_data=fs_byte_data;
 assign audio_busy=audio_owner;
 assign audio_done=fs_file_done && audio_owner;
 assign audio_size=file_size;assign audio_error=file_error;
 assign audio_byte_valid=fs_byte_valid && audio_owner;assign audio_byte_data=fs_byte_data;
 // A finite image-loading phase precedes streaming. Cached navigation never
 // needs SD access, so WAV cannot starve an image transaction or first display.
 assign audio_available=load_state==IDLE && scan_complete &&
                        (found_mask & ~(ready_mask|failed_mask))==0 && file_available && !audio_owner;
 always @(posedge clk or posedge rst)begin
  if(rst)begin audio_owner<=0;audio_slot<=0;audio_start<=0;end
  else begin
   audio_start<=0;
   if(audio_request && audio_available && audio_found_mask[audio_id])begin
    audio_owner<=1;audio_slot<=audio_id;audio_start<=1;
   end else if(audio_owner && fs_file_done)audio_owner<=0;
  end
 end
 wire scan_enable=load_state==IDLE && (found_mask & ~(ready_mask|failed_mask))==0;
 fat32_media files(
  .clk(clk),.rst(rst|fs_reset),.start(fs_start),.scan_enable(scan_enable),.mounted(mounted),
  .scan_done(scan_complete),.fs_error(fs_error),.found_mask(found_mask),.audio_mask(audio_found_mask),.image_audio_map(image_audio_map),
  .file_start(file_start|audio_start),.file_id(audio_owner?{1'b1,audio_slot}:{1'b0,write_buf_idx}),
  .cancel(audio_owner?audio_cancel:(cancel_file|decoder_cancel)),
  .file_available(file_available),.file_busy(file_busy),.file_done(fs_file_done),.file_error(file_error),.file_size(file_size),
  .byte_valid(fs_byte_valid),.byte_data(fs_byte_data),.byte_ready(audio_owner?audio_byte_ready:decoder_byte_ready),
  .sector_req(sector_req),.sector_lba(sector_lba),.sector_busy(sector_busy),.sector_valid(sector_valid),
  .sector_data(sector_data),.sector_index(sector_index),.sector_done(sector_done),.sector_error(sector_error),.sector_ready(sector_ready));
 wire pixel_valid,decode_done;wire [23:0] pixel_data;wire [7:0] decode_error;wire [18:0] pixel_count;
 bmp_resize_decoder decoder(
  .clk(clk),.rst(rst),.start(file_start),.file_size(file_size),.byte_valid(byte_valid),.byte_data(byte_data),
  .byte_ready(decoder_byte_ready),.pixel_ready(write_ready),
  .file_done(file_done),.pixel_valid(pixel_valid),.pixel_data(pixel_data),.done(decode_done),.error(decode_error),
  .cancel(decoder_cancel),.pixel_count(pixel_count));
reg [1:0] init_attempts;
 (* async_reg="true" *) reg [2:0] ack_sync,abort_sync,finish_sync,present_sync,scene_sync,busy_sync;
 reg write_done_seen,source_failed;
 wire finish_pulse=finish_sync[2]^finish_sync[1];
 assign present_pending=present_sync[2]!=commit_toggle;
 assign commit_scene=disp_buf_idx;
 assign write_en=pixel_valid && load_state==READ && !decoder_cancel;
 assign write_data={pixel_data,8'b0};
 assign loading=load_state>=ACK_HI && load_state<=ABORT_LO;
 assign state_code=last_error!=0?4'he:present_pending?4'd6:loading?4'd4:!card_ready?4'd1:!scan_complete?4'd2:4'd0;
 assign picture_number=display_valid?{1'b0,disp_buf_idx}+1'b1:3'd0;
 assign picture_count={2'b0,ready_mask[0]}+{2'b0,ready_mask[1]}+{2'b0,ready_mask[2]}+{2'b0,ready_mask[3]};
 reg period_index;assign period_seconds=period_index?4'd10:4'd5;
 localparam integer MS_CYCLES=CLK_FREQ_HZ>=1000?CLK_FREQ_HZ/1000:1;
 localparam integer MS_BITS=MS_CYCLES>1?$clog2(MS_CYCLES):1;
 reg [MS_BITS-1:0] divider;wire ms_tick=divider==MS_CYCLES-1;
 reg [31:0] uptime_ms;reg [13:0] elapsed_ms;reg [11:0] watchdog_ms;
 reg [1:0] wanted;reg wanted_valid,first_measured,all_measured;
 reg desired_gallery,replay_pending;
 wire audio_settled=audio_playback_complete && audio_playback_sequence==commit_sequence;
 wire [3:0] candidates=found_mask & ~failed_mask;
 wire [3:0] unloaded=candidates & ~ready_mask;
 wire [13:0] dwell_ms=period_index?14'd10000:14'd5000;
 wire auto_due=auto_enabled && audio_settled && display_valid && !menu_active && !desired_gallery && !view_gallery && !present_pending && !busy_sync[2] && !wanted_valid && !replay_pending && !interaction_active && !toggle_auto_event && !cycle_period_event && elapsed_ms>=dwell_ms;
 wire nav_event=!desired_gallery && !menu_active && !menu_event && !gallery_event && (next_event || prev_event || auto_due);
 wire ui_event=next_event || prev_event || toggle_auto_event || cycle_period_event || gallery_event || menu_event;
 function [1:0] first_index;input [3:0] mask;begin
  first_index=mask[0]?0:mask[1]?1:mask[2]?2:3;
 end endfunction
 function [1:0] adjacent;input [1:0] current;input [3:0] mask;input previous;
  integer k;reg [1:0] pos;reg hit;
  begin pos=current;hit=0;adjacent=current;
   for(k=0;k<4;k=k+1) begin
    pos=previous?pos-2'd1:pos+2'd1;
    if(!hit && mask[pos]) begin adjacent=pos;hit=1;end
   end
  end
 endfunction
 wire [1:0] nav_target=adjacent(wanted_valid?wanted:disp_buf_idx,candidates,prev_event);
 always @(posedge clk or posedge rst) begin
  if(rst) begin ack_sync<=0;abort_sync<=0;finish_sync<=0;present_sync<=0;scene_sync<=0;busy_sync<=0;end
  else begin
   scene_sync<={scene_sync[1:0],scene_present_toggle};busy_sync<={busy_sync[1:0],transition_busy};
   ack_sync<={ack_sync[1:0],write_req_ack};abort_sync<={abort_sync[1:0],write_abort_ack};
   finish_sync<={finish_sync[1:0],write_finish_toggle};present_sync<={present_sync[1:0],present_ack_toggle};
  end
 end
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   divider<=0;uptime_ms<=0;elapsed_ms<=0;watchdog_ms<=0;first_frame_ms<=0;all_cached_ms<=0;
   first_measured<=0;all_measured<=0;load_state<=BOOT;init_attempts<=0;
   init_start<=0;fs_start<=0;fs_reset<=0;file_start<=0;cancel_file<=0;
   write_req<=0;write_abort<=0;write_buf_idx<=0;disp_buf_idx<=0;write_done_seen<=0;source_failed<=0;
   display_valid<=0;commit_toggle<=0;commit_sequence<=0;ready_mask<=0;failed_mask<=0;last_error<=0;
   auto_enabled<=0;period_index<=0;wanted<=0;wanted_valid<=0;
   view_gallery<=0;desired_gallery<=0;gallery_focus<=0;replay_pending<=0;
   menu_active<=0;menu_field<=0;local_request<=0;local_field<=0;local_decrease<=0;
  end else begin
   init_start<=0;fs_start<=0;fs_reset<=0;file_start<=0;
   if(ms_tick) begin divider<=0;if(uptime_ms!=32'hffffffff) uptime_ms<=uptime_ms+1'b1;end
   else divider<=divider+1'b1;
   if(!auto_enabled || !audio_settled || !display_valid || menu_active || desired_gallery || view_gallery || present_pending || busy_sync[2] || wanted_valid || replay_pending || interaction_active ||
      next_event || prev_event || toggle_auto_event || cycle_period_event) elapsed_ms<=0;
   else if(ms_tick && elapsed_ms<dwell_ms) elapsed_ms<=elapsed_ms+1'b1;
   if(!loading || (byte_valid && decoder_byte_ready) || pixel_valid || file_done || decode_done || finish_pulse) watchdog_ms<=0;
   else if(ms_tick && watchdog_ms<4095) watchdog_ms<=watchdog_ms+1'b1;
   if((scene_sync[2]^scene_sync[1]) && !first_measured) begin first_measured<=1;first_frame_ms<=uptime_ms;end
   if(scan_complete && ready_mask==15 && !all_measured) begin all_measured<=1;all_cached_ms<=uptime_ms;end
   if(fs_error!=0) last_error<=fs_error;
   if(gallery_event && display_valid)begin
    desired_gallery<=~desired_gallery;gallery_focus<=disp_buf_idx;wanted_valid<=0;menu_active<=0;replay_pending<=0;
   end else if(menu_event && display_valid && !desired_gallery)begin
    menu_active<=~menu_active;menu_field<=0;
   end else if(menu_active)begin
    if(next_event)menu_field<=menu_field==5?0:menu_field+1'b1;
    else if(cycle_period_event)menu_field<=menu_field==0?5:menu_field-1'b1;
    if(toggle_auto_event || prev_event)begin
     if(menu_field==5)begin replay_pending<=1;menu_active<=0;auto_enabled<=0;wanted_valid<=0;end
     else begin local_request<=~local_request;local_field<=menu_field;local_decrease<=prev_event;end
    end
   end else if(desired_gallery)begin
    if(next_event || cycle_period_event)gallery_focus<=adjacent(gallery_focus,ready_mask,cycle_period_event);
    if(toggle_auto_event && ready_mask[gallery_focus])begin
     desired_gallery<=0;wanted<=gallery_focus;wanted_valid<=1;auto_enabled<=0;
    end else if(prev_event)begin desired_gallery<=0;wanted_valid<=0;end
   end else begin
    if(cycle_period_event) period_index<=~period_index;
    if(toggle_auto_event) auto_enabled<=~auto_enabled;
   end
   if(nav_event && display_valid && candidates!=0) begin wanted<=nav_target;wanted_valid<=1;elapsed_ms<=0;replay_pending<=0;end
   // Publish only a fully validated immutable slot. CDC descriptor stays stable until adoption.
   if(!present_pending && !busy_sync[2] && !ui_event && !auto_due) begin
    if(!display_valid && ready_mask!=0) begin
     disp_buf_idx<=first_index(ready_mask);display_valid<=1;commit_toggle<=~commit_toggle;commit_sequence<=commit_sequence+1'b1;
    end else if(display_valid && desired_gallery!=view_gallery)begin
     view_gallery<=desired_gallery;commit_toggle<=~commit_toggle;commit_sequence<=commit_sequence+1'b1;
     if(!desired_gallery && wanted_valid && ready_mask[wanted])begin disp_buf_idx<=wanted;wanted_valid<=0;end
    end else if(display_valid && replay_pending && !view_gallery && !menu_active)begin
     replay_pending<=0;commit_toggle<=~commit_toggle;commit_sequence<=commit_sequence+1'b1;
    end else if(!view_gallery && !menu_active && wanted_valid && ready_mask[wanted]) begin
     wanted_valid<=0;
     // Even a single ready image can repeat its narration during autoplay.
     disp_buf_idx<=wanted;commit_toggle<=~commit_toggle;commit_sequence<=commit_sequence+1'b1;
    end else if(wanted_valid && failed_mask[wanted]) begin
     wanted<=adjacent(wanted,candidates,1'b0);wanted_valid<=candidates!=0;
    end
   end
   if(loading && finish_pulse) write_done_seen<=1;
   case(load_state)
    BOOT: begin init_start<=1;fs_reset<=1;load_state<=INIT_WAIT;end
    INIT_WAIT: if(init_done) begin
     if(card_ready && init_error==0) begin fs_start<=1;last_error<=0;load_state<=IDLE;end
     else if(init_attempts<2) begin init_attempts<=init_attempts+1'b1;load_state<=BOOT;end
     else begin last_error<=8'h80|init_error;load_state<=IDLE;end
    end
    IDLE: begin
     cancel_file<=0;
     if(file_available && !audio_owner && unloaded!=0) begin
      write_buf_idx<=wanted_valid && unloaded[wanted]?wanted:first_index(unloaded);
      write_req<=1;write_done_seen<=0;source_failed<=0;watchdog_ms<=0;load_state<=ACK_HI;
     end else if((next_event || prev_event) && ready_mask==0 &&
          (!card_ready || (scan_complete && (found_mask & ~failed_mask)==0))) begin
      failed_mask<=0;wanted_valid<=0;init_attempts<=0;load_state<=BOOT;
     end
    end
    ACK_HI: if(ack_sync[2]) begin write_req<=0;watchdog_ms<=0;load_state<=ACK_LO;end
      else if(watchdog_ms>=1000) begin write_req<=0;write_abort<=1;last_error<=8'h60;load_state<=ABORT_HI;watchdog_ms<=0;end
    ACK_LO: if(!ack_sync[2]) begin file_start<=1;load_state<=READ;watchdog_ms<=0;end
      else if(watchdog_ms>=1000) begin write_abort<=1;last_error<=8'h61;load_state<=ABORT_HI;watchdog_ms<=0;end
    READ: begin
     if(file_done && file_error!=0) source_failed<=1;
     if(decode_done) begin
      if(decode_error!=0 || source_failed || file_error!=0) begin
       last_error<=(file_error!=0 && file_error!=8'h40)?file_error:decode_error;write_abort<=1;load_state<=ABORT_HI;
      end else load_state<=DRAIN;
      watchdog_ms<=0;
     end else if(watchdog_ms>=2000) begin
      cancel_file<=1;write_abort<=1;last_error<=8'h62;load_state<=ABORT_HI;watchdog_ms<=0;
     end
    end
    DRAIN: if(write_done_seen || finish_pulse) begin
      ready_mask[write_buf_idx]<=1;load_state<=IDLE;watchdog_ms<=0;
     end else if(watchdog_ms>=1000) begin write_abort<=1;last_error<=8'h63;load_state<=ABORT_HI;watchdog_ms<=0;end
    ABORT_HI: if(abort_sync[2] && !file_busy) begin
      write_abort<=0;failed_mask[write_buf_idx]<=1;load_state<=ABORT_LO;watchdog_ms<=0;
     end else if(watchdog_ms>=2000) begin last_error<=8'h6f;load_state<=FAULT;end
    ABORT_LO: if(!abort_sync[2] && !ack_sync[2]) begin load_state<=IDLE;watchdog_ms<=0;end
      else if(watchdog_ms>=1000) begin last_error<=8'h6f;load_state<=FAULT;end
    FAULT: begin write_req<=0;cancel_file<=1;end // Quarantine; cached navigation remains available.
    default:load_state<=BOOT;
   endcase
  end
 end
endmodule
