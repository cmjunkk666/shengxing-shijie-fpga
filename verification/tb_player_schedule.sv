`timescale 1ns/1ps
module tb_player_schedule;
 reg clk=0,rst=1,k1=1,k2=1,ack=0,aback=0,finish=0,present_ack=0,scene_event_token=0;
 always #5 clk=~clk;
 wire req,abort_req,commit,pending,display,loading,scanned,aut;wire [1:0] wi,di;wire [3:0] ready,failed,found,period;wire [7:0] err;
 integer mode=0;integer writes=0,commits=0;reg stuck_ack=0;
 sd_card_bmp #(.CLK_FREQ_HZ(10000),.DEBOUNCE_MS(1),.LONG_PRESS_MS(20),.INIT_DELAY_CYCLES(1)) dut(
 .clk(clk),.rst(rst),.key_next(k1),.key_auto(k2),.state_code(),.bmp_width(16'd640),.bmp_height(16'd480),
 .display_valid(display),.write_finish_toggle(finish),.write_buf_idx(wi),.disp_buf_idx(di),
 .write_req(req),.write_req_ack(ack),.write_abort(abort_req),.write_abort_ack(aback),.write_en(),.write_data(),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),.picture_number(),.picture_count(),.auto_enabled(aut),.period_seconds(period),.loading(loading),.scan_complete(scanned),
 .scene_present_toggle(scene_event_token),.present_ack_toggle(present_ack),.commit_toggle(commit),.commit_sequence(),.commit_scene(),.present_pending(pending),
 .ready_mask(ready),.failed_mask(failed),.found_mask(found),.last_error(err),.sd_retry_count(),.first_frame_ms(),.all_cached_ms(),.last_error_lba());
 reg prevreq=0;
 always @(posedge clk)if(rst)begin ack<=0;aback<=0;finish<=0;present_ack<=0;scene_event_token<=0;prevreq<=0;writes<=0;commits<=0;end
 else begin
  ack<=req && !stuck_ack;aback<=abort_req;prevreq<=req;
  if(req && !prevreq)writes<=writes+1;
  if(dut.file_done && dut.file_error==0)finish<=~finish;
  if(commit!=present_ack)begin present_ack<=commit;scene_event_token<=~scene_event_token;commits<=commits+1;end
 end
 task press(input integer key,input integer n);
  begin @(negedge clk);if(key==1)k1=0;else k2=0;repeat(n)@(negedge clk);k1=1;k2=1;repeat(50)@(negedge clk);end
 endtask
 task expect_scene(input integer n);
  begin wait(!pending && !dut.wanted_valid);repeat(10)@(negedge clk);if(di!=n)$fatal(1,"navigation expected %0d got %0d",n,di);end
 endtask
 integer before_writes,before_commits;
 initial begin
  if(!$value$plusargs("CASE=%d",mode))mode=0;
  repeat(10)@(negedge clk);rst=0;
  wait(ready==(mode==1?4'b1010:4'b1011) && !loading);wait(display && !pending);
  if(mode==1 && (failed!=1 || err!=5))$fatal(1,"transport error lost or retry deadlocked err=%h failed=%b",err,failed);
  before_writes=writes;
  if(mode==0)begin
   expect_scene(0);press(1,60);expect_scene(1);press(1,60);expect_scene(3);press(1,60);expect_scene(0);
   press(2,260);expect_scene(3); // previous skips missing PIC3
  end else begin expect_scene(1);press(1,60);expect_scene(3);press(1,60);expect_scene(1);end
  press(1,260);if(period!=5)$fatal(1,"period control regression");
  before_commits=commits;press(2,60);repeat(52000)@(negedge clk);
  if(!aut || commits<=before_commits)$fatal(1,"auto playback stuck");
  press(1,60);repeat(52000)@(negedge clk);press(2,60);if(aut)$fatal(1,"auto toggle lost");
  if(writes!=before_writes)$fatal(1,"cached navigation reopened writer");
  $display("PASS tb_player_schedule mode=%0d missing-slot navigation, transport failure/abort, auto+manual, cache hits without reload",mode);$finish;
 end
 initial begin #2000000;$fatal(1,"schedule timeout state=%0d ready=%b err=%h",dut.load_state,ready,err);end
endmodule
