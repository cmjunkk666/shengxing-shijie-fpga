`timescale 1ns/1ps
module tb_player_control;
reg clk=0,rst=1,k1=1,k2=1,finish_toggle=0;
always #5 clk=~clk;
wire valid,loading,auto_en,scan_complete;
wire [2:0] pic,count;
wire [3:0] period,state_code;
wire [1:0] wridx,dispidx;
wire [7:0] d0,d1,d2,d3,d4,d5;
integer requests=0,checks=0;
wire commit_toggle, present_pending;
wire [7:0] commit_sequence;
wire [1:0] commit_scene;
reg present_ack=0, auto_ack=1;
always @(posedge clk)
    if(rst) present_ack<=0;
    else if(auto_ack) present_ack<=commit_toggle;
reg [31:0] last_sector;
sd_card_bmp #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(2),.LONG_PRESS_MS(8)) dut(
    .clk(clk),.rst(rst),.key_next(k1),.key_auto(k2),.state_code(state_code),
    .bmp_width(16'd640),.bmp_height(16'd480),.display_valid(valid),
    .write_finish_toggle(finish_toggle),.write_buf_idx(wridx),.disp_buf_idx(dispidx),
    .write_req(),.write_req_ack(1'b1),.write_en(),.write_data(),
    .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),
    .present_ack_toggle(present_ack),.commit_toggle(commit_toggle),
    .commit_sequence(commit_sequence),.commit_scene(commit_scene),.present_pending(present_pending),
    .picture_number(pic),.picture_count(count),.auto_enabled(auto_en),
    .period_seconds(period),.loading(loading),.scan_complete(scan_complete));
player_status_display panel(
    .display_valid(valid),.scan_complete(scan_complete),.loading(loading),
    .picture_number(pic),.picture_count(count),.auto_enabled(auto_en),
    .period_seconds(period),.source_state(state_code),
    .digit0(d0),.digit1(d1),.digit2(d2),.digit3(d3),.digit4(d4),.digit5(d5));
always @(negedge clk) if(!rst && dut.load_start_pulse) begin
    requests=requests+1;last_sector=dut.load_sector;
end
task step(input integer n); repeat(n) @(negedge clk); endtask
task check(input bit cond,input string label_text);
    if(!cond) $fatal(1,"%s pic=%0d count=%0d req=%0d",label_text,pic,count,requests);
    checks=checks+1;$display("PASS %s",label_text);
endtask
task reset_player(input integer images);
    rst=1;k1=1;k2=1;finish_toggle=0;auto_ack=1;
    dut.bmp_read_m0.model_count=images;
    dut.bmp_read_m0.allow_complete=0;
    dut.sd_card_top_m0.model_initialized=1;
    step(5);requests=0;rst=0;step(35);
endtask
task complete_source; dut.bmp_read_m0.allow_complete=1;step(16);endtask
task complete_memory; finish_toggle=~finish_toggle;step(10);endtask
task short1; k1=0;step(5);k1=1;step(9);endtask
task short2; k2=0;step(5);k2=1;step(9);endtask
task long1; k1=0;step(25);k1=1;step(10);endtask
task long2; k2=0;step(25);k2=1;step(10);endtask
integer baseline;
initial begin
    reset_player(4);
    check(count==4 && loading && !valid && requests==1,"scan four and load first");
    check(d0[6:0]==7'b0111111 && d0[7]==0,"loading first shows dash plus dot");
    complete_memory;
    check(!valid && loading,"memory completion alone does not publish");
    complete_source;
    check(valid && pic==1 && !loading,"memory-before-source completion retained");
    check(period==3 && !auto_en && state_code==1,"default period manual and raw state");
    check(d0==8'hf9 && d1==8'h99 && d2==8'h89 && d3==8'hc0 && d4==8'hb0,"six digit normal encoding");
    dut.bmp_read_m0.allow_complete=0;
    long2;
    check(loading && last_sector==7000 && !auto_en,"previous wraps first to fourth without auto toggle");
    complete_source;check(pic==1 && loading,"source completion alone does not publish");
    complete_memory;check(pic==4 && !loading,"source-before-memory publication");
    dut.bmp_read_m0.allow_complete=0;
    short1;check(loading && last_sector==1000,"next wraps fourth to first");
    short1; // queue next while busy
    long2;  // replace queued next with previous
    check(dut.pending_request==2,"busy keeps last requested direction");
    complete_source;complete_memory;step(10);
    check(loading && last_sector==7000 && requests==4,"one pending previous executed from new image");
    complete_memory;step(20);check(pic==4 && !loading && requests==4,"no unwanted next-then-previous sequence");
    baseline=requests;long1;
    check(period==5 && requests==baseline,"runtime period 3 to 5 without next");
    long1;check(period==10 && requests==baseline,"runtime period 5 to 10");
    check(d3==8'hf9 && d4==8'hc0,"ten second digits");
    long1;check(period==3 && requests==baseline,"runtime period wraps to 3");
    short2;check(auto_en,"auto enabled by short release");
    step(2950);check(requests==baseline,"no early autoplay load");
    step(60);check(requests==baseline+1 && loading,"autoplay expires and loads");
    short2;check(!auto_en && loading,"stop while loading lets active load finish");
    complete_memory;step(3100);check(requests==baseline+1 && !loading,"stopped auto has no subsequent load");
    // Exact scheduling boundaries use event injection; ordinary gestures tested above.
    short2;
    @(negedge clk);dut.elapsed_ms=2999;
    force dut.toggle_auto_event=1'b1;
    @(negedge clk);release dut.toggle_auto_event;step(3);
    check(!auto_en && !loading && requests==baseline+1,"stop beats simultaneous timer expiry");
    short2;
    @(negedge clk);dut.elapsed_ms=2999;
    force dut.cycle_period_event=1'b1;
    @(negedge clk);release dut.cycle_period_event;step(3);
    check(period==5 && !loading && dut.elapsed_ms<10,"period change resets expiry");
    // A new event on the exact completion edge must survive the commit.
    reset_player(4);complete_source;complete_memory;
    dut.bmp_read_m0.allow_complete=0;short1;complete_source;
    @(negedge clk);finish_toggle=~finish_toggle;
    wait(dut.frame_complete===1'b1);
    force dut.prev_event=1'b1;
    @(posedge clk);@(negedge clk);release dut.prev_event;step(12);
    check(pic==2 && loading && last_sector==1000,"navigation on completion edge survives commit");
    complete_memory;step(12);
    check(pic==1 && !loading,"completion-edge previous finishes exactly once");
    dut.bmp_read_m0.allow_complete=0;short1;
    baseline=requests;long1;
    check(period==5 && loading && requests==baseline,"period change while busy preserves active load");
    complete_source;complete_memory;
    short2;step(4900);
    check(!loading && requests==baseline,"five second period no early expiry");
    step(110);check(loading && requests==baseline+1,"five second period expires");
    reset_player(1);complete_source;complete_memory;
    short1;long2;short2;
    check(requests==1 && pic==1 && !auto_en && !loading,"single image no redundant reload or autoplay");
    reset_player(0);short1;long2;short2;
    check(requests==0 && !valid && count==0 && !loading && !auto_en,"zero images reject navigation");
    check(d0[6:0]==7'b0111111 && d5[7]==0,"empty media display is not image one");
    reset_player(2);complete_source;complete_memory;
    short1;complete_memory;check(pic==2,"two image next");
    short1;complete_memory;check(pic==1,"two image wrap");
    dut.sd_card_top_m0.model_initialized=0;step(8);
    check(!valid && pic==0 && !auto_en && !loading,"source reinitialization clears control status");
    
    reset_player(4);auto_ack=0;complete_source;complete_memory;
    check(present_pending && loading && requests==1,"pending adoption remains busy");
    baseline=commit_sequence;
    short1;long2;step(40);
    check(requests==1 && commit_sequence==baseline && dispidx==0 && commit_scene==0,
          "old buffer and descriptor protected until reader adoption");
    auto_ack=1;step(12);
    check(requests==2 && loading && wridx==1 && last_sector==7000,
          "latest direction executes only after ownership returned");
    $display("PASS tb_player_control checks=%0d",checks);$finish;
end
initial begin #3000000;$fatal(1,"controller test timeout");end
endmodule
