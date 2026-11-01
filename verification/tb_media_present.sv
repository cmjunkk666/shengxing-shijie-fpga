`timescale 1ns/1ps
module tb_media_present;
reg clk=0,memclk=0,rst=1;
always #20 clk=~clk;
integer memphase=1;
initial begin
    if(!$value$plusargs("MEM_PHASE=%d",memphase)) memphase=1;
    #(memphase);forever #4 memclk=~memclk;
end
reg commit=0,source_valid=0;
reg [1:0] buffer=0,scene=0;
reg [7:0] sequence_in=0;
wire adoption_ack,frame_ack,memreq,memack,adopt;
wire [1:0] selected,adopt_buffer;
reg frame_req=0,pixel_read=0,fifo_empty=0,sof=0,axisvalid=0,ready=1,locked=1;
wire pixels_valid,scene_event,scene_valid;
wire [1:0] scene_out;
wire [7:0] sequence_out;
wire [15:0] late,underflow,protocol;
reg memory_busy=0;
reg [9:0] used_words=400;
wire app_en,fifo_reset;
wire [20:0] app_addr;
reg [7:0] in_flight=0;
wire rd_valid=in_flight[7];
always @(posedge memclk) if(rst)in_flight<=0;else in_flight<={in_flight[6:0],app_en};
media_present_bridge dut(
 .clk(clk),.rst(rst),.commit_toggle(commit),.source_valid(source_valid),
 .commit_buffer(buffer),.commit_scene(scene),.commit_sequence(sequence_in),
 .adoption_ack(adoption_ack),.frame_request(frame_req),.frame_request_ack(frame_ack),
 .memory_request(memreq),.memory_ack(memack),.memory_adopt_toggle(adopt),
 .memory_adopt_buffer(adopt_buffer),.selected_buffer(selected),
 .pixel_read(pixel_read),.fifo_empty(fifo_empty),.axis_sof(sof),
 .axis_valid(axisvalid),.axis_ready(ready),.video_locked(locked),
 .pixels_valid(pixels_valid),.scene_event(scene_event),.scene_valid(scene_valid),
 .scene_id(scene_out),.scene_sequence(sequence_out),
 .late_count(late),.underflow_count(underflow),.protocol_count(protocol));
frame_fifo_read #(.BURST_SIZE(16),.FIFO_DEPTH(512)) reader(
 .rst(rst),.mem_clk(memclk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),
 .Sdr_busy(memory_busy),.Sdr_rd_en(rd_valid),.App_wr_busy(1'b0),.O_rd_busy(),
 .App_rd_en(app_en),.App_rd_addr(app_addr),.read_req(memreq),.read_req_ack(memack),
 .read_adopt_toggle(adopt),.read_adopt_buffer(adopt_buffer),.read_finish(),
 .read_addr_0(21'd0),.read_addr_1(21'd10000),.read_addr_2(21'd20000),.read_addr_3(21'd30000),
 .read_addr_index(selected),.read_len(21'd1024),.fifo_aclr(fifo_reset),.wrusedw(used_words));
integer events=0,checks=0,reads=0;
reg last_adopt=0;
reg [1:0] held_buffer;
always @(negedge memclk) if(!rst) begin
    if(adopt!=last_adopt) begin
        if(in_flight!=0 || rd_valid || fifo_reset || app_addr!=adopt_buffer*10000)
            $fatal(1,"adoption before old transaction drained / wrong base");
        last_adopt=adopt;
    end
    if(app_en) begin
        reads++;
        if(app_addr<adopt_buffer*10000 || app_addr>=adopt_buffer*10000+1024)
            $fatal(1,"read address not owned by adopted frame");
    end
end
always @(negedge clk) if(!rst && scene_event) events++;
task step(input integer n);repeat(n)@(negedge clk);endtask
task check(input bit cond,input string msg);
    if(!cond)$fatal(1,"%s event=%0d late=%0d under=%0d protocol=%0d",msg,events,late,underflow,protocol);
    checks++;$display("PASS %s",msg);
endtask
task submit(input integer b,input integer s);
    #7;
    if(commit!=adoption_ack)$fatal(1,"test attempted overwrite of outstanding descriptor");
    buffer=b;scene=s;sequence_in=sequence_in+1'b1;source_valid=1;commit=~commit;
endtask
task request_frame;
    @(negedge clk);frame_req=1;
    wait(frame_ack);@(negedge clk);frame_req=0;
endtask
task adopted_frame;
    request_frame;wait(dut.frame_ready);step(3);
endtask
task first_pixel;
    @(negedge clk);pixel_read=1;step(1);pixel_read=0;
    step(2);sof=1;axisvalid=1;step(1);sof=0;axisvalid=0;step(2);
endtask
integer before_events;
initial begin
    step(5);rst=0;step(5);
    submit(0,0);step(5);
    check(events==0 && adoption_ack!=commit,"commit is not presentation");
    adopted_frame;
    check(adoption_ack==commit && events==0,"reader adoption returns ownership before SOF");
    first_pixel;check(events==1 && scene_out==0 && sequence_out==1,"first scene tags first valid frame");
    adopted_frame;first_pixel;
    check(events==1,"same frame sequence does not retrigger audio");
    // Restart a real reader while burst responses are in flight.
    used_words=0;wait(app_en);submit(1,1);step(5);request_frame;
    held_buffer=selected;
    while(!dut.frame_ready) begin
        step(1);if(selected!=held_buffer)$fatal(1,"selector changed during handshake");
    end
    used_words=400;step(4);first_pixel;
    check(events==2 && scene_out==1 && sequence_out==2 && reads>0,"in-flight read restart keeps frame identity");
    // Arrival exactly at frame start must defer safely if the request CDC has not arrived.
    @(negedge clk);frame_req=1;
    #1;buffer=0;scene=2;sequence_in=3;commit=~commit;
    wait(frame_ack);@(negedge clk);frame_req=0;
    wait(dut.frame_ready);step(3);first_pixel;
    check(events==2 && adoption_ack!=commit,"boundary commit waits for next frame");
    adopted_frame;first_pixel;
    check(events==3 && scene_out==2 && sequence_out==3,"deferred boundary commit adopted once");
    // Late adoption must not claim a successful first frame, but may return ownership.
    submit(1,3);step(5);memory_busy=1;request_frame;step(5);
    first_pixel;
    check(late==1 && events==3 && !scene_valid,"late adoption suppresses success");
    memory_busy=0;wait(dut.frame_ready);step(3);
    check(adoption_ack==commit && !pixels_valid,"late ownership return does not repair current frame");
    adopted_frame;first_pixel;
    check(events==4 && scene_out==3 && scene_valid,"late frame recovers at next frame boundary");
    adopted_frame;fifo_empty=1;first_pixel;fifo_empty=0;
    check(underflow==1 && !scene_valid && events==4,"FIFO underflow suppresses frame/audio association");
    adopted_frame;first_pixel;
    check(events==5 && scene_valid,"underflow recovery retriggers current scene");
    adopted_frame;ready=0;first_pixel;ready=1;
    check(protocol==1 && events==5 && !scene_valid,"HDMI backpressure is observable");
    adopted_frame;first_pixel;
    check(events==6 && scene_valid,"backpressure recovery");
    locked=0;step(2);check(!scene_valid,"loss of video lock disables scene");
    locked=1;adopted_frame;first_pixel;
    check(events==7 && scene_valid,"lock recovery tags a complete frame");
    rst=1;step(2);
    check(late==0 && underflow==0 && protocol==0 && !scene_valid,"reset clears diagnostics and handshake");
    $display("PASS tb_media_present checks=%0d phase=%0d",checks,memphase);$finish;
end
initial begin #5000000;$fatal(1,"media handshake timeout");end
endmodule
