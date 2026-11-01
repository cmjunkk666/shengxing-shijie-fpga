// One shot per committed scene, then silence. Missing/invalid files use tone.
// SD owns the file/decoder. Pixel clock owns PCM cadence, mixing and FIFO read.
// Scene changes: fade out -> cancel/drain sector -> reset FIFO -> new file.
module wav_scene_player #(parameter FORCE_TONE=0)(
 input wire sd_clk,sd_rst,pcm_clk,pcm_rst,sample_tick,
 input wire run_enable,scene_event,input wire [1:0] scene_id,
 input wire [7:0] scene_sequence,image_audio_map,
 input wire [8:0] volume_gain,
 input wire tone_valid,input wire [23:0] tone_left,
 output reg audio_valid,output reg [23:0] audio_left,
 output wire wav_active,output reg [15:0] underflow_count,
 output wire wav_finished,output wire audio_waiting,
 output reg playback_complete,output reg [7:0] playback_sequence,
 input wire [3:0] found_mask,input wire file_available,
 output wire file_request,output wire [1:0] file_id,output wire file_cancel,
 input wire file_start,file_busy,file_done,input wire [31:0] file_size,
 input wire [7:0] file_error,input wire byte_valid,input wire [7:0] byte_data,
 output wire byte_ready,output reg [7:0] last_error
);
 reg [8:0] mix_gain,smooth_volume,tone_gate;
 reg scene_token,run_registered;
 (* keep="true" *) reg quiet_registered;
 always @(posedge pcm_clk or posedge pcm_rst)
  if(pcm_rst)begin scene_token<=0;run_registered<=0;quiet_registered<=1;end
  else begin
   if(scene_event)scene_token<=~scene_token;
   run_registered<=run_enable;quiet_registered<=mix_gain==0;
  end
 (* async_reg="true" *) reg [2:0] token_sync,run_sync,quiet_sync;
 (* async_reg="true" *) reg [2:0] drained_sync;
 reg seen_token;reg [1:0] wanted_scene;
 localparam RESET=0,WAIT_FILE=1,READ_FILE=2,DRAIN=3,ABORT=4,FINISHED=5;
 reg [2:0] state;reg [5:0] reset_count;
 reg attempted,fifo_reset,stream_enable,stream_finished,fallback_allowed;
 wire quiet;
 wire decoder_cancel,format_valid,decoder_complete,decoded_valid;
 wire [7:0] decoder_error;
 wire [15:0] decoded_sample;
 wire fifo_full,fifo_empty,read_valid;wire [12:0] read_level;
 wire [15:0] read_sample;
 wire read_enable;
 assign file_id=wanted_scene;
 assign file_request=state==WAIT_FILE && !attempted && run_sync[2] &&
                     found_mask[wanted_scene] && file_available && token_sync[2]==seen_token;
 assign file_cancel=state==ABORT || decoder_cancel;
 wav_pcm_decoder decoder(
  .clk(sd_clk),.rst(sd_rst),.start(file_start),.file_size(file_size),
  .byte_valid(byte_valid),.byte_data(byte_data),.byte_ready(byte_ready),
  .file_done(file_done),.file_error(file_error),.cancel(decoder_cancel),
  .format_valid(format_valid),.complete(decoder_complete),.error(decoder_error),
  .sample_valid(decoded_valid),.sample_data(decoded_sample),.sample_ready(!fifo_full));
 pcm_async_fifo fifo(
  .wr_clk(sd_clk),.rd_clk(pcm_clk),.arst(sd_rst|pcm_rst|fifo_reset),
  .wr_en(decoded_valid && state==READ_FILE),.wr_data(decoded_sample),.full(fifo_full),
  .rd_en(read_enable),.rd_data(read_sample),.rd_valid(read_valid),
  .empty(fifo_empty),.rd_level(read_level));
 always @(posedge sd_clk or posedge sd_rst)begin
  if(sd_rst)begin token_sync<=0;run_sync<=0;quiet_sync<=0;end
  else begin
   token_sync<={token_sync[1:0],scene_token};run_sync<={run_sync[1:0],run_registered};
   quiet_sync<={quiet_sync[1:0],quiet};
  end
 end
 always @(posedge sd_clk or posedge sd_rst)begin
  if(sd_rst)begin
   state<=RESET;reset_count<=0;seen_token<=0;wanted_scene<=0;attempted<=0;
   fifo_reset<=1;stream_enable<=0;stream_finished<=0;fallback_allowed<=0;last_error<=0;playback_complete<=0;playback_sequence<=0;
  end else begin
   case(state)
    RESET:begin
     fifo_reset<=1;stream_enable<=0;stream_finished<=0;
     if(reset_count==31)begin fifo_reset<=0;state<=WAIT_FILE;end
     else reset_count<=reset_count+1'b1;
    end
    WAIT_FILE:begin
     if(file_start)begin attempted<=1;fallback_allowed<=0;playback_complete<=0;state<=READ_FILE;end
     // file_available is asserted only after image loading and root scan.
     // No WAV or an already failed attempt must not lock automatic playback.
     else if(file_available && run_sync[2] && (!found_mask[wanted_scene] || attempted))begin
      playback_complete<=1;fallback_allowed<=1;
     end
    end
    READ_FILE:begin
     if(format_valid)stream_enable<=1;
     if(decoder_error!=0)begin last_error<=decoder_error;stream_enable<=0;state<=ABORT;end
     else if(decoder_complete)begin stream_finished<=1;state<=DRAIN;end
    end
    DRAIN:if(quiet_sync[2])begin
     // quiet also starts true before FIFO prefill. Wait for consumer completion.
     if(drained_sync[2])begin stream_enable<=0;playback_complete<=1;state<=FINISHED;end
    end
    ABORT:begin
     stream_enable<=0;
     if(quiet_sync[2] && !file_busy && !file_start)begin
      fifo_reset<=1;reset_count<=0;state<=RESET;
     end
    end
    default:;
   endcase
   if(token_sync[2]!=seen_token)begin
    seen_token<=token_sync[2];wanted_scene<=image_audio_map[{scene_id,1'b0} +: 2];attempted<=0;last_error<=0;
    playback_sequence<=scene_sequence;playback_complete<=0;fallback_allowed<=0;
    stream_enable<=0;state<=ABORT;
   end else if(!run_sync[2] && (state==WAIT_FILE || state==READ_FILE || state==DRAIN))begin
    stream_enable<=0;state<=ABORT;
   end
  end
 end
 (* async_reg="true" *) reg [2:0] enable_sync,end_sync,flush_sync,fallback_sync;
 reg drained,playing;
 reg signed [15:0] held_sample;
 wire enough=read_level>=13'd512 || (end_sync[2] && !fifo_empty);
 wire want_wave=playing && enable_sync[2] && run_enable && !flush_sync[2];
 assign wav_active=mix_gain!=0;
 // Waiting for image loading or WAV prefill is silence, never a warning beep.
 assign audio_waiting=!FORCE_TONE && !wav_active && !wav_finished && !fallback_sync[2];
 assign wav_finished=drained && end_sync[2] && !flush_sync[2];
 assign quiet=quiet_registered;
 assign read_enable=sample_tick && playing && enable_sync[2] && !fifo_empty && !flush_sync[2];
 always @(posedge sd_clk or posedge sd_rst)
  if(sd_rst)drained_sync<=0;else drained_sync<={drained_sync[1:0],drained};
 always @(posedge pcm_clk or posedge pcm_rst)begin
  if(pcm_rst)begin enable_sync<=0;end_sync<=0;flush_sync<=7;fallback_sync<=0;end
  else begin
   enable_sync<={enable_sync[1:0],stream_enable};end_sync<={end_sync[1:0],stream_finished};
   flush_sync<={flush_sync[1:0],fifo_reset};fallback_sync<={fallback_sync[1:0],fallback_allowed};
  end
 end
 always @(posedge pcm_clk or posedge pcm_rst)begin
  if(pcm_rst)begin playing<=0;mix_gain<=0;smooth_volume<=0;tone_gate<=0;held_sample<=0;underflow_count<=0;drained<=0;end
  else begin
   if(read_valid)held_sample<=$signed(read_sample);
   if(flush_sync[2])begin playing<=0;drained<=0;held_sample<=0;end
   if(sample_tick)begin
    if(FORCE_TONE || (fallback_sync[2] && run_enable && !scene_event && !enable_sync[2] && !end_sync[2] && !flush_sync[2]))begin
     if(tone_gate<256)tone_gate<=tone_gate+1'b1;
    end else if(tone_gate!=0)tone_gate<=tone_gate-1'b1;
    if(smooth_volume<volume_gain)smooth_volume<=smooth_volume+1'b1;
    else if(smooth_volume>volume_gain)smooth_volume<=smooth_volume-1'b1;
    if(!enable_sync[2] || !run_enable || flush_sync[2])playing<=0;
    else if(!playing && enough)playing<=1;
    else if(playing && fifo_empty)begin
     playing<=0;
     if(!end_sync[2] && underflow_count!=16'hffff)underflow_count<=underflow_count+1'b1;
    end
    if(want_wave && mix_gain<256)mix_gain<=mix_gain+1'b1;
    else if(!want_wave && mix_gain!=0)mix_gain<=mix_gain-1'b1;
    if(end_sync[2] && fifo_empty && mix_gain==0 && !flush_sync[2])drained<=1;
   end
  end
 end
 // Retain the proven tone cadence. All source paths have the same additional
 // three clocks of latency; ACR observes this final valid, including silence.
 reg [2:0] valid_pipe;
 reg signed [25:0] wav_product,tone_product,mix_product;
 reg signed [15:0] wav_scaled,tone_scaled,tone_delayed;
 reg [8:0] mix0,mix1;
 wire signed [26:0] combined=$signed({tone_delayed[15],tone_delayed})+($signed(mix_product)>>>8);
 function [15:0] clamp;input signed [26:0] v;
 begin clamp=v>32767?16'h7fff:v < -32768?16'h8000:v[15:0];end endfunction
 always @(posedge pcm_clk or posedge pcm_rst)begin
  if(pcm_rst)begin
   valid_pipe<=0;audio_valid<=0;audio_left<=0;wav_product<=0;tone_product<=0;mix_product<=0;
   wav_scaled<=0;tone_scaled<=0;tone_delayed<=0;mix0<=0;mix1<=0;
  end else begin
   valid_pipe<={valid_pipe[1:0],tone_valid};audio_valid<=valid_pipe[2];
   if(tone_valid)begin
    wav_product<=held_sample*$signed({1'b0,smooth_volume});
    // Once a valid WAV is accepted, keep its pauses and EOF silent.
    // Do not mix the built-in melody into natural recordings or their ending.
    tone_product<=$signed(tone_left[23:8])*$signed({1'b0,tone_gate});mix0<=mix_gain;
   end
   if(valid_pipe[0])begin wav_scaled<=wav_product>>>11;tone_scaled<=tone_product>>>8;mix1<=mix0;end
   if(valid_pipe[1])begin mix_product<=wav_scaled*$signed({1'b0,mix1});tone_delayed<=tone_scaled;end
   if(valid_pipe[2])audio_left<={clamp(combined),8'b0};
  end
 end
endmodule
