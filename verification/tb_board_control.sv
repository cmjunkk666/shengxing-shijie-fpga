`timescale 1ns/1ps
module tb_board_control;
reg clk=0,pclk=0,mclk=0,rst=1,k1=1,k2=1,finish_toggle=0;
always #5 clk=~clk;
always #20 pclk=~pclk;
initial begin #3; forever #4 mclk=~mclk; end
wire valid,loading,auto_en,scan_complete,commit,pending,adopt_ack,wr_req,wr_en;
wire [2:0] pic,count;
wire [3:0] period,sc;
wire [1:0] wi,di,scene,selected,adopt_buffer;
wire [7:0] sequence_id;
wire [31:0] data;
reg [2:0] wr_ack_pipe=0;
wire wr_ack=wr_ack_pipe[2];
always @(posedge mclk or posedge rst)
 if(rst)wr_ack_pipe<=0;else wr_ack_pipe<={wr_ack_pipe[1:0],wr_req};
integer words=0,loads=0,commits=0,checks=0;
reg lastcommit=0;
always @(posedge clk or posedge rst) begin
 if(rst)begin words<=0;finish_toggle<=0;end
 else if(wr_req)words<=0;
 else if(wr_en)begin
  if(words==255)begin finish_toggle<=~finish_toggle;words<=0;end
  else words<=words+1;
 end
end
always @(negedge clk)if(!rst)begin
 if(dut.load_start_pulse)loads++;
 if(commit!=lastcommit)begin commits++;lastcommit=commit;end
end
sd_card_bmp #(.CLK_FREQ_HZ(1000),.DEBOUNCE_MS(2),.LONG_PRESS_MS(8),
 .SCAN_MAX_SECTOR(8),.SCAN_TARGET_COUNT(2)) dut(
 .clk(clk),.rst(rst),.key_next(k1),.key_auto(k2),.state_code(sc),
 .bmp_width(16'd128),.bmp_height(16'd2),.display_valid(valid),
 .write_finish_toggle(finish_toggle),.write_buf_idx(wi),.disp_buf_idx(di),
 .write_req(wr_req),.write_req_ack(wr_ack),.write_en(wr_en),.write_data(data),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),
 .picture_number(pic),.picture_count(count),.auto_enabled(auto_en),
 .period_seconds(period),.loading(loading),.scan_complete(scan_complete),
 .present_ack_toggle(adopt_ack),.commit_toggle(commit),.commit_sequence(sequence_id),
 .commit_scene(scene),.present_pending(pending));
reg frame_req=0;
wire frame_ack,mreq,mack,adopt_toggle,ren;
wire [23:0] raddr;
reg [7:0] rpipe=0;
integer ft=0;
always @(posedge pclk or posedge rst)
 if(rst)begin ft<=0;frame_req<=0;end else begin
 if(ft==199)begin ft<=0;frame_req<=1;end else ft<=ft+1;
 if(frame_ack)frame_req<=0;
 end
always @(posedge mclk or posedge rst)
 if(rst)rpipe<=0;else rpipe<={rpipe[6:0],ren};
frame_fifo_read #(.ADDR_BITS(24)) reader(
 .rst(rst),.mem_clk(mclk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(1'b0),.Sdr_rd_en(rpipe[7]),.App_wr_busy(wr_en),.O_rd_busy(),
 .App_rd_en(ren),.App_rd_addr(raddr),.read_req(mreq),.read_req_ack(mack),
 .read_adopt_toggle(adopt_toggle),.read_adopt_buffer(adopt_buffer),.read_finish(),
 .read_addr_0(24'd0),.read_addr_1(24'd1024),.read_addr_2(24'd0),.read_addr_3(24'd0),
 .read_addr_index(selected),.read_len(24'd256),.fifo_aclr(),.wrusedw(10'd0));
media_present_bridge bridge(.clk(pclk),.rst(rst),.commit_toggle(commit),.source_valid(valid),
 .commit_buffer(di),.commit_scene(scene),.commit_sequence(sequence_id),.adoption_ack(adopt_ack),
 .frame_request(frame_req),.frame_request_ack(frame_ack),.memory_request(mreq),.memory_ack(mack),
 .memory_adopt_toggle(adopt_toggle),.memory_adopt_buffer(adopt_buffer),.selected_buffer(selected),
 .pixel_read(1'b0),.fifo_empty(1'b0),.axis_sof(1'b0),.axis_valid(1'b0),
 .axis_ready(1'b1),.video_locked(1'b1),.pixels_valid(),.scene_event(),.scene_valid(),
 .scene_id(),.scene_sequence(),.late_count(),.underflow_count(),.protocol_count());
task step(input integer n);repeat(n)@(negedge clk);endtask
task short1;k1=0;step(5);k1=1;step(20);endtask
task short2;k2=0;step(5);k2=1;step(20);endtask
task long1;k1=0;step(25);k1=1;step(20);endtask
task next_commits(input integer target,input integer budget);
 integer j;
 begin
  j=0;
  while(commits<target && j<budget)begin step(1);j++;end
  if(commits<target)$fatal(1,"load stalled target=%0d actual=%0d loading=%0b source_state=%0d pending=%0b",target,commits,loading,sc,pending);
  checks++;
 end
endtask
integer n,j,saved_loads;
initial begin
 step(7);rst=0;next_commits(1,25000);step(1000);
 if(count!=2 || pic!=1 || loading)$fatal(1,"first frame failed");
 short2;
 n=commits;next_commits(n+1,20000);step(1000);
 short1;n=commits;next_commits(n+2,35000);
 long1;if(period!=5 || !auto_en)$fatal(1,"long key lost auto");
 n=commits;next_commits(n+2,40000);
 $display("PASS normal autoplay + KEY1 short/long, real BMP and frame adoption");
 // Ensure idle dwell, then corrupt exactly one image header at the card boundary.
 short2;step(10000);
 dut.sd_card_top_m0.corrupt_next=1;
 n=commits;short1;
 next_commits(n+1,25000);
 step(1000);
 if(loading)$fatal(1,"failure recovery did not acknowledge buffer");
 short2;n=commits;next_commits(n+2,40000);

 short2;step(10000);
 dut.sd_card_top_m0.corrupt_all=1;
 n=commits;saved_loads=loads;short1;step(20000);
 if(sc!=14 || loading || auto_en || commits!=n || loads!=saved_loads+3)
  $fatal(1,"persistent header error must stop after 3 attempts without commit");
 step(10000);
 if(loads!=saved_loads+3)$fatal(1,"unbounded retry");
 dut.sd_card_top_m0.corrupt_all=0;short1;
 next_commits(n+1,20000);step(1000);
 if(loading || sc==14)$fatal(1,"manual retry after E failed");
 // Interrupt scanning/loading at several asynchronous offsets; both CDC tokens reset.
 for(j=0;j<6;j++)begin
  #3;rst=1;step(5);lastcommit=0;commits=0;rst=0;
  step(200+j*431);
  #2;rst=1;step(5);lastcommit=0;commits=0;rst=0;
  next_commits(1,25000);step(1000);
  if(pic!=1 || loading || pending || count!=2)$fatal(1,"reset first image recovery");
 end
 $display("PASS persistent-header bounded retry, manual recovery, six reset offsets");
 $display("PASS tb_board_control checks=%0d loads=%0d commits=%0d one corrupt header recovered",checks,loads,commits);
 $finish;
end
initial begin #5000000;$fatal(1,"board test timeout");end
endmodule
