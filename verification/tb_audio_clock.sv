`timescale 1ns/1ps
module tb_audio_clock;
reg clk=0,rst=1;
always #20 clk=~clk;
wire tick,valid;
wire [19:0] cts,n;
reg [4:0] pipeline=0;
always @(posedge clk) if(rst) pipeline<=0;else pipeline<={pipeline[3:0],tick};
audio_sample_tick dut(.clk(clk),.rst(rst),.sample_tick(tick));
audio_arc_calculate acr(.I_clk(clk),.I_rst(rst),.I_audio_valid(pipeline[4]),
    .O_acr_valid(valid),.O_acr_cts(cts),.O_acr_n(n));
integer cycle=0,count=0,last=0,acr_count=0,gap520=0,gap521=0;
initial begin
    repeat(5) @(negedge clk);
    if(valid!==0 || cts!==0 || n!==0) $fatal(1,"ACR reset unknown");
    rst=0;
    repeat(312500) begin
        @(negedge clk);cycle=cycle+1;
        if(tick) begin
            count=count+1;
            if(last!=0) begin
                if(cycle-last==520) gap520++;
                else if(cycle-last==521) gap521++;
                else $fatal(1,"sample interval %0d",cycle-last);
            end
            last=cycle;
        end
        if(cycle%3125==0 && count!=cycle/3125*6) $fatal(1,"rational sample count");
        if(valid) begin
            acr_count++;
            if(count<49 || cts!=25000 || n!=6144) $fatal(1,"ACR incomplete/wrong %0d",cts);
        end
    end
    if(count!=600 || gap520!=100 || gap521!=499 || acr_count!=12)
        $fatal(1,"clock totals %0d %0d %0d %0d",count,gap520,gap521,acr_count);
    rst=1;repeat(2)@(negedge clk);
    if(valid!==0 || cts!==0) $fatal(1,"ACR re-reset");
    $display("PASS tb_audio_clock samples=600 complete_acr_windows=12");$finish;
end
endmodule
