// Mono content in two channels. 16-bit PCM is LEFT-aligned into 24 bits.
// Quarter-wave peak=12000 before PCM_SHIFT; gain 0..256; round ties away from zero.
// Top: shift 3, first-start ramp 512 ms, scene/stop fade up to 128 ms.
module pcm_scene_audio #(
    parameter integer TEST_MODE=0,
    parameter integer NOTE_SAMPLES=12000,
    parameter integer PCM_SHIFT=0,
    parameter integer STARTUP_STEP_SAMPLES=0,
    parameter integer SCENE_FADE_STEP_SAMPLES=0
)(
    input wire clk, rst, sample_tick,
    input wire run_enable, scene_event,
    input wire [1:0] scene_id,
    input wire [8:0] volume_gain,
    output reg audio_valid,
    output reg [23:0] audio_left, audio_right,
    output wire signed [15:0] pcm_probe,
    output wire pcm_probe_valid,
    output reg [1:0] active_scene,
    output reg [8:0] envelope_gain,
    output reg [31:0] sample_count,
    output reg [15:0] deadline_miss_count
);
reg [31:0] phase;
reg [1:0] note_index, pending_scene;
reg [13:0] note_age;
reg pending, active;
reg [7:0] ramp_error;
wire [8:0] ramp_sum={1'b0,ramp_error}+9'd16;
wire [1:0] ramp_step=(ramp_sum>=240)?2'd2:2'd1;
wire [1:0] target_scene=scene_event?scene_id:pending_scene;
wire change_pending=pending || scene_event;
wire [31:0] increment=(TEST_MODE!=0)?32'd89478485:note_increment({active_scene,note_index});
wire [8:0] capped_volume=(volume_gain>256)?9'd256:volume_gain;
// One multiplication: volume is a ceiling on the automatic envelope.
// Slew the manual/transition volume by one gain unit per sample (max 5.34 ms).
reg [8:0] smooth_volume;
always @(posedge clk or posedge rst)
 if(rst)smooth_volume<=0;
 else if(sample_tick)begin
  if(smooth_volume<capped_volume)smooth_volume<=smooth_volume+1'b1;
  else if(smooth_volume>capped_volume)smooth_volume<=smooth_volume-1'b1;
 end
reg [8:0] startup_gain;
wire [8:0] note_volume=(envelope_gain<smooth_volume)?envelope_gain:smooth_volume;
wire [8:0] sample_gain=(startup_gain<note_volume)?startup_gain:note_volume;
localparam integer START_BITS=(STARTUP_STEP_SAMPLES<2)?1:$clog2(STARTUP_STEP_SAMPLES);
localparam integer FADE_BITS=(SCENE_FADE_STEP_SAMPLES<2)?1:$clog2(SCENE_FADE_STEP_SAMPLES);
reg [START_BITS-1:0] startup_count;
reg [FADE_BITS-1:0] scene_fade_count;

always @(posedge clk or posedge rst)
    if(rst) begin startup_gain<=STARTUP_STEP_SAMPLES==0?256:0;startup_count<=0;end
    else if(sample_tick) begin
        if(STARTUP_STEP_SAMPLES==0) startup_gain<=256;
        else if(!run_enable && envelope_gain==0) begin startup_gain<=0;startup_count<=0;end
        else if(active && run_enable && startup_gain<256) begin
            if(startup_count==STARTUP_STEP_SAMPLES-1) begin
                startup_count<=0;startup_gain<=startup_gain+1'b1;
            end else startup_count<=startup_count+1'b1;
        end
    end

function signed [15:0] quarter;
    input [6:0] address;
    begin
        case(address)
            7'd0: quarter = 16'sd0;
            7'd1: quarter = 16'sd294;
            7'd2: quarter = 16'sd589;
            7'd3: quarter = 16'sd883;
            7'd4: quarter = 16'sd1176;
            7'd5: quarter = 16'sd1469;
            7'd6: quarter = 16'sd1761;
            7'd7: quarter = 16'sd2052;
            7'd8: quarter = 16'sd2341;
            7'd9: quarter = 16'sd2629;
            7'd10: quarter = 16'sd2916;
            7'd11: quarter = 16'sd3201;
            7'd12: quarter = 16'sd3483;
            7'd13: quarter = 16'sd3764;
            7'd14: quarter = 16'sd4043;
            7'd15: quarter = 16'sd4319;
            7'd16: quarter = 16'sd4592;
            7'd17: quarter = 16'sd4863;
            7'd18: quarter = 16'sd5131;
            7'd19: quarter = 16'sd5395;
            7'd20: quarter = 16'sd5657;
            7'd21: quarter = 16'sd5915;
            7'd22: quarter = 16'sd6169;
            7'd23: quarter = 16'sd6420;
            7'd24: quarter = 16'sd6667;
            7'd25: quarter = 16'sd6910;
            7'd26: quarter = 16'sd7148;
            7'd27: quarter = 16'sd7383;
            7'd28: quarter = 16'sd7613;
            7'd29: quarter = 16'sd7838;
            7'd30: quarter = 16'sd8059;
            7'd31: quarter = 16'sd8274;
            7'd32: quarter = 16'sd8485;
            7'd33: quarter = 16'sd8691;
            7'd34: quarter = 16'sd8891;
            7'd35: quarter = 16'sd9087;
            7'd36: quarter = 16'sd9276;
            7'd37: quarter = 16'sd9460;
            7'd38: quarter = 16'sd9638;
            7'd39: quarter = 16'sd9811;
            7'd40: quarter = 16'sd9978;
            7'd41: quarter = 16'sd10138;
            7'd42: quarter = 16'sd10293;
            7'd43: quarter = 16'sd10441;
            7'd44: quarter = 16'sd10583;
            7'd45: quarter = 16'sd10719;
            7'd46: quarter = 16'sd10848;
            7'd47: quarter = 16'sd10971;
            7'd48: quarter = 16'sd11087;
            7'd49: quarter = 16'sd11196;
            7'd50: quarter = 16'sd11299;
            7'd51: quarter = 16'sd11394;
            7'd52: quarter = 16'sd11483;
            7'd53: quarter = 16'sd11565;
            7'd54: quarter = 16'sd11640;
            7'd55: quarter = 16'sd11708;
            7'd56: quarter = 16'sd11769;
            7'd57: quarter = 16'sd11823;
            7'd58: quarter = 16'sd11870;
            7'd59: quarter = 16'sd11910;
            7'd60: quarter = 16'sd11942;
            7'd61: quarter = 16'sd11967;
            7'd62: quarter = 16'sd11986;
            7'd63: quarter = 16'sd11996;
            7'd64: quarter = 16'sd12000;
            default: quarter=0;
        endcase
    end
endfunction
function signed [15:0] sine_sample;
    input [7:0] address;
    reg [6:0] folded;
    reg signed [15:0] magnitude;
    begin
        folded=address[6] ? 7'd64-{1'b0,address[5:0]} : {1'b0,address[5:0]};
        magnitude=quarter(folded);
        sine_sample=address[7] ? -magnitude : magnitude;
    end
endfunction
function [31:0] note_increment;
    input [3:0] address;
    begin
        case(address)
            4'd0: note_increment = 32'd46819719;
            4'd1: note_increment = 32'd58989149;
            4'd2: note_increment = 32'd70150316;
            4'd3: note_increment = 32'd58989149;
            4'd4: note_increment = 32'd39370534;
            4'd5: note_increment = 32'd46819719;
            4'd6: note_increment = 32'd58989149;
            4'd7: note_increment = 32'd46819719;
            4'd8: note_increment = 32'd52553357;
            4'd9: note_increment = 32'd58989149;
            4'd10: note_increment = 32'd78741067;
            4'd11: note_increment = 32'd58989149;
            4'd12: note_increment = 32'd23409859;
            4'd13: note_increment = 32'd35075158;
            4'd14: note_increment = 32'd46819719;
            4'd15: note_increment = 32'd35075158;
            default: note_increment=32'd46819660;
        endcase
    end
endfunction
function signed [15:0] quantize;
    input signed [25:0] value;
    reg signed [26:0] extended_value, rounded_value, scaled_value;
    begin
        extended_value={value[25],value};
        // Arithmetic shift rounds downward; negative rounding bias is one smaller.
        rounded_value=extended_value + (value<0 ? (27'sd128<<PCM_SHIFT)-1 : (27'sd128<<PCM_SHIFT));
        scaled_value=rounded_value >>> (8+PCM_SHIFT);
        if(scaled_value>32767) quantize=16'sh7fff;
        else if(scaled_value < -32768) quantize=16'sh8000;
        else quantize=scaled_value[15:0];
    end
endfunction

// Events are retained between sample ticks. Newest scene wins even on the
// zero-gain adoption tick. A new event never restarts an in-progress fade.
always @(posedge clk or posedge rst) begin
    if(rst) begin
        phase<=0; note_index<=0; note_age<=0; active_scene<=0;
        pending_scene<=0; pending<=0; active<=0; envelope_gain<=0; ramp_error<=0; scene_fade_count<=0;
    end else begin
        if(scene_event) begin pending_scene<=scene_id; pending<=1; end
        if(sample_tick) begin
            if(!run_enable || change_pending || !active) begin
                if(envelope_gain!=0 && smooth_volume!=0) begin
                    phase<=phase+increment;
                    if(SCENE_FADE_STEP_SAMPLES==0) begin
                        envelope_gain <= (envelope_gain<=ramp_step)?9'd0:envelope_gain-ramp_step;
                        ramp_error <= (ramp_sum>=240)?ramp_sum-240:ramp_sum;
                    end else if(scene_fade_count==SCENE_FADE_STEP_SAMPLES-1) begin
                        scene_fade_count<=0;envelope_gain<=envelope_gain-1'b1;
                    end else scene_fade_count<=scene_fade_count+1'b1;
                end else begin
                    phase<=0; note_index<=0; note_age<=0; envelope_gain<=0; ramp_error<=0; scene_fade_count<=0;
                    active<=run_enable;
                    if(run_enable) begin active_scene<=target_scene; pending<=0; end
                end
            end else begin
                scene_fade_count<=0;
                phase<=phase+increment;
                if(note_age==NOTE_SAMPLES-1 && TEST_MODE==0) begin
                    note_age<=0; note_index<=note_index+1'b1;
                    phase<=0; envelope_gain<=0; ramp_error<=0;
                end else begin
                    if(note_age<NOTE_SAMPLES-1) note_age<=note_age+1'b1;
                    if(TEST_MODE==0 && note_age>=NOTE_SAMPLES-240) begin
                        envelope_gain <= (envelope_gain<=ramp_step)?9'd0:envelope_gain-ramp_step;
                        ramp_error <= (ramp_sum>=240)?ramp_sum-240:ramp_sum;
                    end else if(envelope_gain<256) begin
                        envelope_gain <= (envelope_gain+ramp_step>=256)?9'd256:envelope_gain+ramp_step;
                        ramp_error <= (ramp_sum>=240)?ramp_sum-240:ramp_sum;
                    end
                end
            end
        end
    end
end

// Calculation and output schedules are separate. Output is always tick+4
// clocks, including silence or a deliberately fault-injected calculation miss.
reg [3:0] due;
reg [1:0] calc_state;
reg signed [15:0] wave_reg, result_sample;
reg signed [9:0] gain_reg;
reg signed [25:0] product;
reg result_ready;
always @(posedge clk or posedge rst) begin
    if(rst) begin
        due<=0; calc_state<=0; wave_reg<=0; gain_reg<=0; product<=0;
        result_sample<=0; result_ready<=0; audio_valid<=0;
        audio_left<=0; audio_right<=0; sample_count<=0; deadline_miss_count<=0;
    end else begin
        due<={due[2:0],sample_tick};
        audio_valid<=due[3];
        case(calc_state)
            0: if(sample_tick) begin
                wave_reg<=sine_sample(phase[31:24]);
                gain_reg<=$signed({1'b0,sample_gain});
                calc_state<=1;
            end
            1: begin product<=wave_reg*gain_reg; calc_state<=2; end
            2: begin result_sample<=quantize(product); result_ready<=1; calc_state<=0; end
            default: calc_state<=0;
        endcase
        if(due[3]) begin
            audio_left<=result_ready?{result_sample,8'b0}:24'd0;
            audio_right<=result_ready?{result_sample,8'b0}:24'd0;
            result_ready<=0;
            sample_count<=sample_count+1'b1;
            if(!result_ready && deadline_miss_count!=16'hffff)
                deadline_miss_count<=deadline_miss_count+1'b1;
        end
    end
end
assign pcm_probe=$signed(audio_left[23:8]);
assign pcm_probe_valid=audio_valid;
endmodule
