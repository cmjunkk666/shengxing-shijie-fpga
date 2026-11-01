`timescale 1ns/1ps
module tb_board_audio_reset;
reg clk=0,rst=1,tick=0,enable=0,event_in=0;
always #5 clk=~clk;
wire valid;
wire [23:0] left,right;
wire [8:0] env;
wire [1:0] scene;
wire [15:0] misses;
wire [31:0] count;
pcm_scene_audio #(.PCM_SHIFT(3),.STARTUP_STEP_SAMPLES(96),.SCENE_FADE_STEP_SAMPLES(24)) dut(
 .clk(clk),.rst(rst),.sample_tick(tick),.run_enable(enable),.scene_event(event_in),
 .scene_id(2'd1),.volume_gain(9'd256),.audio_valid(valid),.audio_left(left),.audio_right(right),
 .pcm_probe(),.pcm_probe_valid(),.active_scene(scene),.envelope_gain(env),
 .sample_count(count),.deadline_miss_count(misses));
reg request=1;
wire grst,drst;
reset_startup_guard #(.HOLD_CYCLES(8)) guard(.clk(clk),.arst(request),.rst(grst));
reset_release_sync domain_reset(.clk(clk),.arst(grst),.rst(drst));
integer i,j,expected,gain,oldenv,first_gain=-1,full_gain=-1;
reg [31:0] phase;
real value,wave;
integer f,minimum=0,maximum=0;
task sample;
 begin
  @(negedge clk);tick=1;phase=dut.phase;
  gain=dut.envelope_gain;
  if(dut.startup_gain<gain)gain=dut.startup_gain;
  wave=12000.0*$sin(6.283185307179586*(phase>>24)/256.0);
  expected=$rtoi(wave>=0?wave+0.5:wave-0.5);
  value=expected*gain/2048.0;
  expected=$rtoi(value>=0?value+0.5:value-0.5);
  @(negedge clk);tick=0;event_in=0;
  repeat(4)@(negedge clk);
  if(!valid || left!==right || left[7:0]!=0 || $signed(left[23:8])!=expected || misses!=0)
    $fatal(1,"board audio numeric/valid mismatch sample=%0d expected=%0d actual=%0d",i,expected,$signed(left[23:8]));
  if($signed(left[23:8])>maximum)maximum=$signed(left[23:8]);
  if($signed(left[23:8])<minimum)minimum=$signed(left[23:8]);
  $fdisplay(f,"%0d %0d %0d %0d %0d",i,$signed(left[23:8]),dut.startup_gain,env,scene);
 end
endtask
initial begin
 f=$fopen("board_audio_trace.txt","w");
 repeat(4)@(negedge clk);rst=0;request=0;
 repeat(10)begin @(negedge clk);if(!grst)$fatal(1,"startup reset released too early");end
 repeat(8)@(negedge clk);
 if(grst || drst)$fatal(1,"startup reset did not release");
 #2;request=1;#1;if(!grst || !drst)$fatal(1,"PLL loss must assert reset asynchronously");
 @(negedge clk);request=0;repeat(18)@(negedge clk);
 if(grst || drst)$fatal(1,"reset did not recover");
 enable=1;
 for(i=0;i<36000;i++)begin
  sample;
  if(dut.startup_gain>0 && first_gain<0)first_gain=i;
  if(dut.startup_gain==256 && full_gain<0)full_gain=i;
 end
 if(first_gain!=96 || full_gain!=24576 || maximum!=1500 || minimum!=-1500)
  $fatal(1,"startup/level mismatch first=%0d full=%0d min=%0d max=%0d",first_gain,full_gain,minimum,maximum);
 // 36,000 samples is a note boundary; move into sustain, then scene transition.
 for(j=0;j<1000;j++)begin i++;sample;end
 oldenv=env;event_in=1;
 for(j=0;j<6200;j++)begin
  i++;sample;
  if(scene==1 && env!=0 && j<6144)$fatal(1,"scene changed before 128 ms fade");
 end
 if(scene!=1)$fatal(1,"scene change not adopted");
 enable=0;
 for(j=0;j<6300;j++)begin i++;sample;end
 if(left!=0 || env!=0 || dut.startup_gain!=0)$fatal(1,"mute must produce digital zero");
 enable=1;
 for(j=0;j<300;j++)begin i++;sample;end
 if(dut.startup_gain>4)$fatal(1,"reacquisition must start slowly");
 $fclose(f);
 $display("PASS tb_board_audio_reset samples=%0d min=%0d max=%0d startup_samples=%0d scene_fade=6144 reset_guard=PASS",i,minimum,maximum,full_gain);
 $finish;
end
initial begin #10000000;$fatal(1,"audio reset timeout");end
endmodule
