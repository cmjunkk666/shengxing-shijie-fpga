// Independent video-frame window verifies delivered PCM count.
// 800*525 pixel clocks * 6/3125 = 806.4 samples/frame.
// Modulo-2^32 subtraction handles sample-counter wrap.
module audio_cadence_monitor #(parameter MIN_SAMPLES=806, MAX_SAMPLES=807)(
    input wire clk,rst,frame_start,
    input wire [31:0] sample_count,
    output reg cadence_fault
);
reg [31:0] previous_count;
wire [31:0] delta=sample_count-previous_count;
wire outside_window;
generate
    if(MIN_SAMPLES%2==0 && MAX_SAMPLES==MIN_SAMPLES+1) begin: consecutive_pair
        // The two accepted values differ only in bit zero: one equality check.
        assign outside_window=(delta[31:1] != (MIN_SAMPLES>>1));
    end else begin: general_window
        assign outside_window=(delta<MIN_SAMPLES || delta>MAX_SAMPLES);
    end
endgenerate
reg primed;
always @(posedge clk or posedge rst) begin
    if(rst) begin primed<=0;previous_count<=0;cadence_fault<=0;end
    else if(frame_start) begin
        previous_count<=sample_count;primed<=1;
        if(primed && outside_window) cadence_fault<=1;
    end
end
endmodule
