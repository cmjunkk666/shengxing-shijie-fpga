// Asynchronous assertion, three local edges before reset release.
module reset_release_sync(input wire clk, arst, output wire rst);
(* async_reg = "true" *) reg [2:0] release_pipe;
always @(posedge clk or posedge arst)
    if(arst) release_pipe <= 3'b111;
    else release_pipe <= {release_pipe[1:0],1'b0};
assign rst = release_pipe[2];
endmodule


// Reference-clock startup qualification. Any reset/PLL loss asserts immediately.
// Counter starts only after the async request has passed the local synchronizer.
module reset_startup_guard #(
    parameter integer HOLD_CYCLES=1000000
)(input wire clk, arst, output wire rst);
wire local_reset;
reset_release_sync u_guard_sync(.clk(clk),.arst(arst),.rst(local_reset));
localparam integer BITS=(HOLD_CYCLES<2)?1:$clog2(HOLD_CYCLES+1);
reg [BITS-1:0] count;
reg waiting;
always @(posedge clk or posedge arst)
    if(arst) begin count<=0;waiting<=1;end
    else if(local_reset) begin count<=0;waiting<=1;end
    else if(waiting) begin
        if(count==HOLD_CYCLES-1) waiting<=0;
        else count<=count+1'b1;
    end
assign rst=arst || local_reset || waiting;
endmodule
