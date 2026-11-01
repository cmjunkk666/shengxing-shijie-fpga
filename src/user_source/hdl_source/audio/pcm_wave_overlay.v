// 128 columns x 16 consecutive samples = 42.67 ms per snapshot, 48 kHz.
// Each column retains min AND max from all 16 samples, not one decimated point.
// The completed bank is held until VS. Capture waits for that swap; independent
// peak measurement continues on every PCM sample, including the swap interval.
// Input is the actual post-volume PCM sent to HDMI (synth or WAV).
module pcm_wave_overlay(
 input wire clk,rst,de,vs,enable,history_mode,clear_history,input wire [23:0] rgb,
 input wire sample_valid,input wire signed [15:0] sample,
 output wire de_out,vs_out,output reg [23:0] rgb_out
);
 reg [9:0] x,x1;reg [8:0] y,y1;reg old_de,old_vs,de1,vs1,active;
 wire frame_tick=vs && !old_vs;
 reg read_bank,write_bank,bank_full,have_wave;
 reg [6:0] column;reg [3:0] sample_number;
 // Preserve extrema at the finest display resolution (one pixel / 32 PCM
 // units) until the complete 2048-sample window is known. Discarding the low
 // five bits is exact for every supported scale, including negative samples.
 // Each displayed snapshot uses ONE scale, so its waveform is not compressed
 // or clipped sample by sample. The maximum visual gain is 4x the old /128.
 wire signed [10:0] display_value=sample[15:5];
 reg signed [10:0] low_value,high_value;
 wire signed [10:0] new_low=sample_number==0 || display_value<low_value?display_value:low_value;
 wire signed [10:0] new_high=sample_number==0 || display_value>high_value?display_value:high_value;
 reg [21:0] columns[0:255];reg [21:0] samples1;
 reg [3:0] capture_shift,wave_shift;
 wire [3:0] sample_shift;
 function [3:0] snapshot_shift;input [15:0] peak;
 begin
  // Both polarities fit within +/-39 pixels, including signed -32768.
  if(peak<=16'd1248)snapshot_shift=4'd5;
  else if(peak<=16'd2496)snapshot_shift=4'd6;
  else if(peak<=16'd4992)snapshot_shift=4'd7;
  else if(peak<=16'd9984)snapshot_shift=4'd8;
  else if(peak<=16'd19968)snapshot_shift=4'd9;
  else snapshot_shift=4'd10;
 end endfunction
 function [7:0] display_sample;input [10:0] pcm;input [3:0] amount;
 begin
  // Only these six scales are reachable. Fixed slices avoid a general
  // 16-bit barrel shifter; snapshot_shift guarantees the result fits.
  case(amount)
   5:display_sample=pcm[7:0];
   6:display_sample=pcm[8:1];
   7:display_sample=pcm[9:2];
   8:display_sample=pcm[10:3];
   9:display_sample={pcm[10],pcm[10:4]};
   default:display_sample={{2{pcm[10]}},pcm[10:5]};
  endcase
 end endfunction
 reg [15:0] peak_acc;
 // Fixed, monotonic display scale; never normalize away scene differences.
 // Quiet samples get 16x the old linear scale, with compressed loud peaks.
 // This affects the yellow indicator only, not PCM or the configured V bar.
 function [8:0] meter_scale;input [15:0] amplitude;
 begin
  if(amplitude<1024)meter_scale=amplitude>>3;
  else if(amplitude<4096)meter_scale=9'd128+((amplitude-16'd1024)>>5);
  else if(amplitude<8192)meter_scale=9'd224+((amplitude-16'd4096)>>7);
  else meter_scale=9'd256;
 end endfunction
 reg [8:0] meter_width;
 wire [15:0] frame_peak;
 wire [8:0] meter_target=meter_scale(frame_peak);
 wire [8:0] meter_decay=meter_width>12?meter_width-9'd12:9'd0;
 wire [15:0] magnitude=sample[15]?(~sample+16'd1):sample;
 assign sample_shift=snapshot_shift(magnitude);
 assign frame_peak=sample_valid && magnitude>peak_acc?magnitude:peak_acc;
 wire [8:0] local_x=x-10'd64;
 reg [23:0] rgb1;
 // 128 peaks, one per 2400 PCM samples (50 ms): 6.4 seconds of history.
 // Commit one completed bucket at VS, so the ring's origin is stable per frame.
 // This is a peak-amplitude envelope, not a frequency spectrum or SPL meter.
 reg [11:0] history_samples;
 reg [15:0] history_peak;
 reg [5:0] history_pending_value;
 reg history_pending,active_history;
 reg [6:0] history_write,history_origin;
 reg [7:0] history_count;
 reg [5:0] history[0:127];
 reg [5:0] history_value1;
 wire [15:0] bucket_peak=magnitude>history_peak?magnitude:history_peak;
 wire [8:0] bucket_height=bucket_peak[15:7];
 wire history_commit=frame_tick && history_pending && !clear_history;
 wire [6:0] history_read=history_origin+local_x[8:2];
 wire [9:0] history_local_x=x1-10'd64;
 wire [7:0] history_column={1'b0,history_local_x[8:2]};
 wire history_visible=history_column>=(8'd128-history_count);
 // A mode-specific Chinese label belongs to the overlay, so it also works
 // for replacement BMP/WAV files and disappears when SOUND VIEW is off.
 `include "../user_source/hdl_source/audio/audio_view_labels.vh"
 wire [8:0] label_y=y-9'd286;
 reg [15:0] label_pixels;
 // Read each word only where it is drawn. The synchronous read still pairs
 // with x1/y1; holding a word across its 4/16 pixels adds no video latency.
 // Capture remains active in both modes so switching preserves live history.
 wire label_read=active && de && x>=64 && x<320 && y>=286 && y<302 && x[3:0]==0;
 wire graph_read=active && de && x>=64 && x<576 && y>=312 && y<=392 && x[1:0]==0;
 always @(posedge clk)
  if(label_read)label_pixels<=audio_label_rom[{active_history,label_y[3:0],local_x[7:4]}];
 always @(posedge clk)begin
  if(history_commit)history[history_write]<=history_pending_value;
  if(graph_read && active_history)history_value1<=history[history_read];
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   history_samples<=0;history_peak<=0;history_pending_value<=0;history_pending<=0;
   history_write<=0;history_origin<=0;history_count<=0;active_history<=0;
  end else begin
   if(frame_tick)active_history<=history_mode;
   if(clear_history)begin
    history_samples<=0;history_peak<=0;history_pending<=0;
    history_write<=0;history_origin<=0;history_count<=0;
   end else begin
    if(history_commit)begin
     history_write<=history_write+1'b1;history_origin<=history_write+1'b1;
     if(history_count<128)history_count<=history_count+1'b1;
     history_pending<=0;
    end
    if(sample_valid)begin
     if(history_samples==2399)begin
      history_samples<=0;history_peak<=0;history_pending<=1;
      history_pending_value<=bucket_height>39?6'd39:bucket_height[5:0];
     end else begin history_samples<=history_samples+1'b1;history_peak<=bucket_peak;end
    end
   end
  end
 end
 always @(posedge clk)begin
  if(sample_valid && !bank_full && !clear_history && sample_number==15)columns[{write_bank,column}]<={new_high,new_low};
  if(graph_read && !active_history && have_wave)samples1<=columns[{read_bank,local_x[8:2]}];
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   x<=0;x1<=0;y<=0;y1<=0;old_de<=0;old_vs<=0;de1<=0;vs1<=0;active<=0;rgb1<=0;
   read_bank<=0;write_bank<=1;bank_full<=0;have_wave<=0;column<=0;sample_number<=0;
   low_value<=0;high_value<=0;peak_acc<=0;meter_width<=0;
   capture_shift<=5;wave_shift<=7;
  end else begin
   old_de<=de;old_vs<=vs;de1<=de;vs1<=vs;rgb1<=rgb;x1<=x;y1<=y;
   if(de)x<=x+1'b1;else x<=0;
   if(frame_tick)begin
    y<=0;active<=enable;peak_acc<=0;
    // Immediate attack, roughly 0.36 s maximum decay; transient peaks stay visible.
    meter_width<=meter_target>=meter_decay?meter_target:meter_decay;
   end
   else begin
    if(old_de && !de)y<=y+1'b1;
    if(sample_valid && magnitude>peak_acc)peak_acc<=magnitude;
   end
   if(clear_history)begin
    // A scene change discards a partial capture and its old scale together.
    read_bank<=0;write_bank<=1;bank_full<=0;have_wave<=0;column<=0;sample_number<=0;
    low_value<=0;high_value<=0;capture_shift<=5;wave_shift<=7;
   end else if(frame_tick && bank_full)begin
    read_bank<=write_bank;write_bank<=~write_bank;bank_full<=0;have_wave<=1;column<=0;sample_number<=0;
    wave_shift<=capture_shift;capture_shift<=5;
   end else if(sample_valid && !bank_full)begin
    low_value<=new_low;high_value<=new_high;
    // max(scale(abs(sample))) == scale(max(abs(sample))).
    if(sample_shift>capture_shift)capture_shift<=sample_shift;
    if(sample_number==15)begin
     sample_number<=0;
     if(column==127)bank_full<=1;else column<=column+1'b1;
    end else sample_number<=sample_number+1'b1;
   end
  end
 end
 wire signed [10:0] screen_value=11'sd352-$signed({2'b0,y1});
 // Shift only for rendering. PCM, yellow meter and LEVEL history retain
 // their original samples and fixed amplitude scales.
 wire signed [7:0] minimum=display_sample(samples1[10:0],wave_shift);
 wire signed [7:0] maximum=display_sample(samples1[21:11],wave_shift);
 assign de_out=de1;assign vs_out=vs1;
 always @*begin
  rgb_out=rgb1;
  if(active && de1 && x1>=52 && x1<576 && y1>=284 && y1<304)begin
   rgb_out=24'h101e2c;
   if(x1<58 || y1==303)rgb_out=24'h60e8b0;
   if(x1>=64 && x1<320 && y1>=286 && y1<302 && label_pixels[15-x1[3:0]])
    rgb_out=24'he4fff2;
  end
  if(active && de1 && x1>=64 && x1<576 && y1>=304 && y1<400)begin
   rgb_out={2'b0,rgb1[23:18],2'b0,rgb1[15:10],2'b0,rgb1[7:2]};
   if(x1==64 || x1==575 || y1==304 || y1==399)rgb_out=24'h60bfa0;
   else if(y1==352 || x1[6:0]==64)rgb_out=24'h35485c;
   if(active_history)begin
    if(history_visible && y1>=312 && y1<=392 &&
       screen_value<=$signed({1'b0,history_value1}) && screen_value>=-$signed({1'b0,history_value1}))rgb_out=24'h60e8b0;
   end else if(have_wave && y1>=312 && y1<=392 && screen_value>=minimum && screen_value<=maximum)rgb_out=24'h60e8b0;
   // Six-pixel-thick responsive level bar, from the actual outgoing PCM.
   if(y1>=306 && y1<312 && x1>=68 && x1<324)
    rgb_out=x1-68<meter_width?24'hffd45c:24'h35485c;
  end
 end
endmodule
