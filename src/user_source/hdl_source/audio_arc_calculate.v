// Measure COMPLETE intervals between final PCM submissions, not reset-to-first.
// For N=6144, 48 sample intervals at 25 MHz / 48 kHz produce CTS=25000.
module audio_arc_calculate #(parameter ACR_N=6144)(
    input wire I_clk, I_rst, I_audio_valid,
    output reg O_acr_valid,
    output reg [19:0] O_acr_cts, O_acr_n
);
localparam integer AUDIO_DIV=ACR_N/128;
localparam integer COUNT_BITS=(AUDIO_DIV<2)?1:$clog2(AUDIO_DIV);
reg [COUNT_BITS-1:0] intervals;
reg [19:0] clocks;
reg primed;
always @(posedge I_clk or posedge I_rst) begin
    if(I_rst) begin
        intervals<=0; clocks<=0; primed<=0;
        O_acr_valid<=0; O_acr_cts<=0; O_acr_n<=0;
    end else begin
        O_acr_valid<=0;
        if(primed) clocks<=clocks+1'b1;
        if(I_audio_valid) begin
            if(!primed) begin primed<=1; clocks<=0; intervals<=0; end
            else if(intervals==AUDIO_DIV-1) begin
                O_acr_valid<=1; O_acr_cts<=clocks+1'b1; O_acr_n<=ACR_N;
                clocks<=0; intervals<=0;
            end else intervals<=intervals+1'b1;
        end
    end
end
endmodule
