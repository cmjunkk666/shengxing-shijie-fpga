`timescale 1ns/1ps
module tb_pcm_audio;
reg clk=0,rst=1,tick=0,enable=0,event_in=0;
reg [1:0] scene=0;
reg [8:0] volume=256;
always #5 clk=~clk;
wire valid,testvalid;
wire [23:0] left,right,tl,tr;
wire signed [15:0] probe;
wire pv;
wire [15:0] misses,tm;
wire [31:0] count;
wire [8:0] gain;
wire [1:0] active_scene;
pcm_scene_audio dut(.clk(clk),.rst(rst),.sample_tick(tick),.run_enable(enable),
    .scene_event(event_in),.scene_id(scene),.volume_gain(volume),
    .audio_valid(valid),.audio_left(left),.audio_right(right),
    .pcm_probe(probe),.pcm_probe_valid(pv),.active_scene(active_scene),
    .envelope_gain(gain),.sample_count(count),.deadline_miss_count(misses));
pcm_scene_audio #(.TEST_MODE(1)) tone(.clk(clk),.rst(rst),.sample_tick(tick),.run_enable(enable),
    .scene_event(1'b0),.scene_id(2'd0),.volume_gain(9'd256),
    .audio_valid(testvalid),.audio_left(tl),.audio_right(tr),
    .pcm_probe(),.pcm_probe_valid(),.active_scene(),.envelope_gain(),
    .sample_count(),.deadline_miss_count(tm));
integer f,ft,tablef,qf,i,old_gain,old_scene;
reg [31:0] old_phase,test_phase;
integer effective_gain,test_gain;
integer switches=0;
task sample;
    begin
        @(negedge clk);tick=1;
        old_phase=dut.phase;old_gain=gain;old_scene=active_scene;
        test_phase=tone.phase;test_gain=tone.envelope_gain;
        effective_gain=(volume>256)?256:volume;
        if(old_gain<effective_gain) effective_gain=old_gain;
        @(negedge clk);tick=0;event_in=0;
        repeat(3) @(negedge clk);
        if(valid) $fatal(1,"output early");
        @(negedge clk);
        if(!valid || !testvalid || left!==right || tl!==tr || pv!==valid || probe!==$signed(left[23:8]))
            $fatal(1,"PCM valid/channel/probe mismatch at %0d",i);
        if(left[7:0]!==0 || tr[7:0]!==0) $fatal(1,"PCM alignment");
        if(old_scene!=active_scene) begin
            switches++;
            if(old_gain!=0) $fatal(1,"scene switched before zero gain");
        end
        $fdisplay(f,"%0d %0d %0d %0d %0d %0d %0d %0d",i,old_phase,effective_gain,
                  $signed(left[23:8]),active_scene,gain,dut.note_index,dut.note_age);
        $fdisplay(ft,"%0d %0d %0d %0d",i,test_phase,test_gain,$signed(tl[23:8]));
        @(negedge clk);
        if(valid || testvalid) $fatal(1,"valid wider than one clock");
    end
endtask
initial begin
    f=$fopen("pcm_trace.txt","w");ft=$fopen("tone_trace.txt","w");
    tablef=$fopen("sine_trace.txt","w");qf=$fopen("quantize_trace.txt","w");
    repeat(5)@(negedge clk);rst=0;
    for(i=0;i<256;i++) $fdisplay(tablef,"%0d %0d",i,$signed(dut.sine_sample(i)));
    for(i=-8388736;i<=8388736;i=i+127)
        $fdisplay(qf,"%0d %0d",i,$signed(dut.quantize(i)));
    $fclose(tablef);$fclose(qf);
    for(i=0;i<65000;i++) begin
        if(i==10) begin enable=1;event_in=1;scene=0;end
        if(i==12100) begin event_in=1;scene=1;end
        if(i==12110) begin event_in=1;scene=2;end
        if(i==12120) begin event_in=1;scene=3;end
        if(i==12400 && active_scene!=3) $fatal(1,"newest scene not adopted");
        if(i==24000) enable=0;
        if(i==24260 && (gain!=0 || left!=0)) $fatal(1,"mute fade did not finish");
        if(i==24300) begin enable=1;event_in=1;scene=1;end
        if(i==37000) begin event_in=1;scene=0;end
        if(i==40000) volume=0;
        if(i==40500) volume=128;
        if(i==41000) volume=511;
        sample;
        if(i<10 && left!=0) $fatal(1,"startup not silent");
        if(misses!=0 || tm!=0 || count!=i+1) $fatal(1,"sample loss");
    end
    @(negedge clk);tick=1;
    @(negedge clk);tick=0;
    repeat(3)@(negedge clk);
    force dut.result_ready=0;
    @(negedge clk);
    if(!valid || left!=0 || misses!=1) $fatal(1,"deadline fallback");
    release dut.result_ready;
    i=65001;sample;
    if(misses!=1 || left==0) $fatal(1,"deadline recovery");
    rst=1;repeat(2)@(negedge clk);
    if(valid!==0 || misses!==0 || left!==0) $fatal(1,"reset outputs");
    $fclose(f);$fclose(ft);
    $display("PASS tb_pcm_audio samples=65002 scene_switches=%0d deadline_faults=1",switches);
    $finish;
end
initial begin #100000000;$fatal(1,"PCM timeout");end
endmodule
