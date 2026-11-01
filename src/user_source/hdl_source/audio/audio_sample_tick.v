// 25 MHz / 48 kHz = 3125 / 6. Clock ENABLE, never a generated clock.
// General reduced rational parameters also allow accelerated simulation.
module audio_sample_tick #(
    parameter integer NUMERATOR=6, DENOMINATOR=3125,
    parameter integer ACC_BITS=$clog2(DENOMINATOR)
)(input wire clk, rst, output reg sample_tick);
reg [ACC_BITS-1:0] accumulator;
always @(posedge clk or posedge rst) begin
    if(rst) begin accumulator<=0; sample_tick<=0; end
    else if(accumulator >= DENOMINATOR-NUMERATOR) begin
        accumulator<=accumulator-(DENOMINATOR-NUMERATOR); sample_tick<=1;
    end else begin accumulator<=accumulator+NUMERATOR; sample_tick<=0; end
end
endmodule
