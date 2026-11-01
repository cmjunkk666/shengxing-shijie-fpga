`timescale 1ns/1ps
module tb_cache_pipeline;
 reg sc=0,mc=0,vc=0,rst=1,key1=1,key2=1;
 always #5 sc=~sc;always #12.5 mc=~mc;always #20 vc=~vc;
 wire wrreq,wrack,wabort,waack,we,finish;wire [31:0] wd;reg finish_toggle=0;reg scene_present_toggle=0;wire scene_event;
 always @(posedge vc) if(rst)scene_present_toggle<=0;else if(scene_event)scene_present_toggle<=~scene_present_toggle;
 wire [1:0] wi,di,scene_commit;wire display,commit,pending,present_ack;wire [7:0] seq,error;
 wire [3:0] ready,failed,found,status,period;wire [2:0] number,count;wire automatic_play,loading,scanned;
 wire [31:0] first_ms,all_ms;wire [15:0] retries;
 sd_card_bmp #(.CLK_FREQ_HZ(100000),.DEBOUNCE_MS(1),.LONG_PRESS_MS(10),.INIT_DELAY_CYCLES(10)) player(
 .clk(sc),.rst(rst),.key_next(key1),.key_auto(key2),.state_code(status),.bmp_width(16'd640),.bmp_height(16'd480),
 .display_valid(display),.write_finish_toggle(finish_toggle),.write_buf_idx(wi),.disp_buf_idx(di),
 .write_req(wrreq),.write_req_ack(wrack),.write_abort(wabort),.write_abort_ack(waack),.write_en(we),.write_data(wd),
 .SD_nCS(),.SD_DCLK(),.SD_MOSI(),.SD_MISO(1'b1),.picture_number(number),.picture_count(count),
 .auto_enabled(automatic_play),.period_seconds(period),.loading(loading),.scan_complete(scanned),
 .scene_present_toggle(scene_present_toggle),.present_ack_toggle(present_ack),.commit_toggle(commit),.commit_sequence(seq),.commit_scene(scene_commit),.present_pending(pending),
 .ready_mask(ready),.failed_mask(failed),.found_mask(found),.last_error(error),.sd_retry_count(retries),
 .first_frame_ms(first_ms),.all_cached_ms(all_ms),.last_error_lba());
 wire request,ack,hs0,vs0,de0,hs,vs,de,pixel_read;
 wire [23:0] raw,axis_data;wire axis_user,axis_valid,axis_last;
 wire memreq,memack,adopt,empty,pixels_valid,scene_valid;wire [1:0] selected,adopt_buffer,scene;
 wire [7:0] scene_sequence;wire [15:0] late,underflow,protocol;
 wire ren,wen;wire [20:0] ra,wa;wire [31:0] memwd,fifo_data;
 reg [31:0] memory[0:1228799];reg [7:0] read_valid=0;reg [31:0] read_pipe[0:7];
 integer k,pixels_written=0,slot=0;reg ack_old=0;reg [31:0] expected_word;
 always @(posedge mc)begin
  if(rst)begin read_valid<=0;finish_toggle<=0;ack_old<=0;pixels_written=0;end
  else begin
   ack_old<=wrack;
   if(wrack && !ack_old)begin pixels_written=0;slot=wi;end
   if(finish)finish_toggle<=~finish_toggle;
   read_valid<={read_valid[6:0],ren};read_pipe[0]<=memory[ra];
   for(k=1;k<8;k++)read_pipe[k]<=read_pipe[k-1];
   if(wen)begin
    if(ren)$fatal(1,"read/write arbitration overlap");
    if(wa>=1228800 || ready[slot])$fatal(1,"write outside free cache");
    if(wa!=slot*307200+(479-pixels_written/640)*640+pixels_written%640)$fatal(1,"write orientation/address %0d pixel %0d",wa,pixels_written);
    expected_word={8'(slot*40+17),8'(pixels_written/640),8'(pixels_written%640),8'd0};
    if(memwd!==expected_word)$fatal(1,"FIFO write data mismatch actual=%h expected=%h",memwd,expected_word);
    memory[wa]<=memwd;pixels_written++;
   end
  end
 end
 always @(posedge sc)if(!rst && we && frame.write_buf.full_flag)$fatal(1,"write FIFO overflow");
 video_timing_data timing_dut(.video_clk(vc),.rst(rst),.read_req(request),.read_req_ack(ack),.hs(hs0),.vs(vs0),.de(de0));
 video_delay delay_dut(.video_clk(vc),.rst(rst),.read_en(pixel_read),.read_data(fifo_data[31:8]),
 .hs(hs0),.vs(vs0),.de(de0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(raw));
 video_rgb_to_axis_640x480 axis_dut(.I_clk(vc),.I_rst(rst),.I_vs(vs),.I_de(de),.I_rgb(pixels_valid?raw:24'd0),
 .O_video_user(axis_user),.O_video_valid(axis_valid),.O_video_last(axis_last),.O_video_data(axis_data));
 media_present_bridge bridge(.clk(vc),.rst(rst),.commit_toggle(commit),.source_valid(display),
 .commit_buffer(di),.commit_scene(scene_commit),.commit_sequence(seq),.adoption_ack(present_ack),
 .frame_request(request),.frame_request_ack(ack),.memory_request(memreq),.memory_ack(memack),
 .memory_adopt_toggle(adopt),.memory_adopt_buffer(adopt_buffer),.selected_buffer(selected),
 .pixel_read(pixel_read),.fifo_empty(empty),.axis_sof(axis_user),.axis_valid(axis_valid),.axis_ready(1'b1),.video_locked(1'b1),
 .pixels_valid(pixels_valid),.scene_event(scene_event),.scene_valid(scene_valid),.scene_id(scene),.scene_sequence(scene_sequence),
 .late_count(late),.underflow_count(underflow),.protocol_count(protocol));
 frame_read_write #(.BURST_SIZE(256)) frame(.rst(rst),.mem_clk(mc),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .App_rd_en(ren),.App_rd_addr(ra),.Sdr_rd_en(read_valid[7]),.Sdr_rd_dout(read_pipe[7]),
 .read_clk(vc),.read_req(memreq),.read_req_ack(memack),.read_adopt_toggle(adopt),.read_adopt_buffer(adopt_buffer),.read_fifo_empty(empty),.read_finish(),
 .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd614400),.read_addr_3(21'd921600),
 .read_addr_index(selected),.read_len(21'd307200),.read_en(pixel_read && pixels_valid && !empty),.read_data(fifo_data),
 .App_wr_en(wen),.App_wr_addr(wa),.App_wr_din(memwd),.App_wr_dm(),.write_clk(sc),
 .write_req(wrreq),.write_req_ack(wrack),.write_abort(wabort),.write_abort_ack(waack),.write_finish(finish),
 .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd614400),.write_addr_3(21'd921600),
 .write_addr_index(wi),.write_len(21'd307200),.write_en(we),.write_data(wd));
 integer mode=0,frames=0,pixels=0,frame_slot=0,events=0,verified=0,read_snapshot=0,n=0;
 reg [23:0] expected_pixel;reg [3:0] expected_mask;
 always @(negedge vc)if(!rst)begin
  if(late!=0 || underflow!=0 || protocol!=0)$fatal(1,"40MHz pipeline fault late=%0d under=%0d protocol=%0d",late,underflow,protocol);
  if(scene_event)begin events++;if(scene!=frame_slot)$fatal(1,"scene mismatch");end
  if(axis_valid && pixels_valid)begin
   if(axis_user)begin if(frames!=0 && pixels!=307200)$fatal(1,"frame shortened");frames++;pixels=0;frame_slot=selected;end
   expected_pixel={8'(frame_slot*40+17),8'(479-pixels/640),8'(pixels%640)};
   if(axis_data!==expected_pixel)$fatal(1,"display pixel %0d slot %0d actual=%h expected=%h",pixels,frame_slot,axis_data,expected_pixel);
   pixels++;verified++;
  end
 end
 task press(input integer which,input integer cycles);
  begin @(negedge sc);if(which==1)key1=0;else key2=0;
   repeat(cycles)@(negedge sc);if(which==1)key1=1;else key2=1;repeat(200)@(negedge sc);
  end
 endtask
 task wait_scene(input integer target);
  begin wait(scene_valid && scene==target && !pending);repeat(10)@(negedge vc);end
 endtask
 initial begin
  if(!$value$plusargs("CASE=%d",mode))mode=0;
  expected_mask=mode==1?4'b1011:mode==7?4'b1110:4'b1111;
  repeat(20)@(negedge sc);rst=0;
  wait(display);$display("first cache committed t=%0t ready=%b",$time,ready);
  if(ready==expected_mask)$fatal(1,"first display delayed until all cached");
  if(mode==7 && ready[0])$fatal(1,"failed first image displayed");
  wait(scene_valid);
  if(mode==0)begin
   // Navigate while another image loads; latest direction stays bounded.
   wait(found==15 && loading);press(1,300);wait_scene(1);$display("navigation during preload passed t=%0t",$time);
  end
  wait(scanned && ready==expected_mask && !loading);$display("all available cached t=%0t ready=%b",$time,ready);wait(!pending);
  if(mode==7 && failed!=1)$fatal(1,"failed load did not safely abort %b",failed);
  read_snapshot=player.sectors.requests;
  // Four manual next operations wrap the available subset without any SD access.
  for(n=0;n<4;n++)begin
   press(1,300);wait(!player.wanted_valid && !pending);repeat(5000)@(negedge sc);
  end
  press(2,1300);wait(!player.wanted_valid && !pending); // long KEY2 previous
  press(1,1300);if(period!=5)$fatal(1,"long KEY1 period event");
  press(2,300);if(!automatic_play)$fatal(1,"auto enable");
  // Accelerated controller ms ticks preserve real video/frame clocks.
  repeat(1800000)@(negedge sc);
  press(1,300);repeat(4000000)@(negedge sc);
  press(2,300);if(automatic_play)$fatal(1,"auto disable");
  if(player.sectors.requests!=read_snapshot)$fatal(1,"cache navigation still reads SD");
  if(events<4 || verified<614400)$fatal(1,"insufficient presentation coverage");
  $display("PASS tb_cache_pipeline mode=%0d ready=%b failed=%b frames=%0d verified_pixels=%0d events=%0d sectors=%0d first_ms=%0d all_ms=%0d",mode,ready,failed,frames,verified,events,read_snapshot,first_ms,all_ms);$finish;
 end
 initial begin forever begin #50000000;$display("cache progress t=%0t state=%0d fs=%0d ready=%b found=%b wanted=%b/%0d err=%h scene=%0d valid=%b",$time,player.load_state,player.files.state,ready,found,player.wanted_valid,player.wanted,error,scene,scene_valid);end end
 initial begin #600000000;$fatal(1,"cache timeout mode=%0d state=%0d ready=%b found=%b error=%h",mode,player.load_state,ready,found,error);end
endmodule
