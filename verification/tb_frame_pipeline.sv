
`timescale 1ns/1ps
// Actual video timing, delay, generated FIFO RTL and reader. SDRAM alone is
// modeled with eight-cycle returned data. Pixel pattern encodes buffer+address.
module tb_frame_pipeline;
reg clk=0,memclk=0,rst=1;
always #20 clk=~clk;
initial begin #3;forever #4 memclk=~memclk;end
wire request,ack,hs0,vs0,de0,hs,vs,de,read_en;
wire [23:0] raw;
wire memreq,memack,adopt;
wire [1:0] selected,adopt_buffer;
reg commit=0,source_valid=0;
reg [1:0] source_buffer=0,source_scene=0;
reg [7:0] source_sequence=0;
wire source_ack,pixels_valid,scene_event,scene_valid;
wire [1:0] scene;
wire [7:0] sequence_out;
wire [15:0] late,underflow,protocol;
wire axis_user,axis_valid,axis_last;
wire [23:0] axis_data;
wire app_en,fifo_reset,empty;
wire [20:0] app_addr;
wire [31:0] fifo_data;
wire [8:0] used_words;
reg [7:0] mem_valid_pipe=0;
reg [31:0] mem_data_pipe[0:7];
integer j;
always @(posedge memclk) begin
    if(rst) begin mem_valid_pipe<=0;for(j=0;j<8;j++)mem_data_pipe[j]<=0;end
    else begin
        mem_valid_pipe<={mem_valid_pipe[6:0],app_en};
        mem_data_pipe[0]<={(3'b0+{3'b0,app_addr}+24'd1),8'd0};
        for(j=1;j<8;j++)mem_data_pipe[j]<=mem_data_pipe[j-1];
    end
end
video_timing_data timing_dut(.video_clk(clk),.rst(rst),.read_req(request),.read_req_ack(ack),
 .hs(hs0),.vs(vs0),.de(de0));
video_delay delay_dut(.video_clk(clk),.rst(rst),.read_en(read_en),.read_data(fifo_data[31:8]),
 .hs(hs0),.vs(vs0),.de(de0),.hs_r(hs),.vs_r(vs),.de_r(de),.vout_data(raw));
video_rgb_to_axis_640x480 axis_dut(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),
 .I_rgb(pixels_valid?raw:24'd0),.O_video_user(axis_user),.O_video_valid(axis_valid),
 .O_video_last(axis_last),.O_video_data(axis_data));
media_present_bridge bridge(
 .clk(clk),.rst(rst),.commit_toggle(commit),.source_valid(source_valid),
 .commit_buffer(source_buffer),.commit_scene(source_scene),.commit_sequence(source_sequence),
 .adoption_ack(source_ack),.frame_request(request),.frame_request_ack(ack),
 .memory_request(memreq),.memory_ack(memack),.memory_adopt_toggle(adopt),
 .memory_adopt_buffer(adopt_buffer),.selected_buffer(selected),
 .pixel_read(read_en),.fifo_empty(empty),.axis_sof(axis_user),.axis_valid(axis_valid),
 .axis_ready(1'b1),.video_locked(1'b1),.pixels_valid(pixels_valid),
 .scene_event(scene_event),.scene_valid(scene_valid),.scene_id(scene),
 .scene_sequence(sequence_out),.late_count(late),.underflow_count(underflow),.protocol_count(protocol));
frame_fifo_read #(.BURST_SIZE(256)) reader(
 .rst(rst),.mem_clk(memclk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .Sdr_rd_en(mem_valid_pipe[7]),.App_wr_busy(1'b0),.O_rd_busy(),
 .App_rd_en(app_en),.App_rd_addr(app_addr),.read_req(memreq),.read_req_ack(memack),
 .read_adopt_toggle(adopt),.read_adopt_buffer(adopt_buffer),.read_finish(),
 .read_addr_0(21'd0),.read_addr_1(21'd307200),.read_addr_2(21'd0),.read_addr_3(21'd0),
 .read_addr_index(selected),.read_len(21'd307200),.fifo_aclr(fifo_reset),.wrusedw({1'b0,used_words}));
rfifo_32_32_512 fifo(
 .clkr(clk),.clkw(memclk),.rst(fifo_reset),.we(mem_valid_pipe[7]),
 .re(read_en && pixels_valid && !empty),.di(mem_data_pipe[7]),.dout(fifo_data),
 .wrusedw(used_words),.rdusedw(),.empty_flag(empty),.full_flag(),.valid(),.afull(),.aempty());
integer frames=0,pixels=0,events=0,verified=0,frame_buffer=0;
always @(negedge clk) if(!rst) begin
    if(late!=0 || underflow!=0 || protocol!=0) $fatal(1,"real pipeline fault late=%0d under=%0d protocol=%0d",late,underflow,protocol);
    if(scene_event) begin
        events++;
        if(scene!=frame_buffer || sequence_out!=frame_buffer+1) $fatal(1,"scene / pixel frame mismatch");
    end
    if(axis_valid && pixels_valid) begin
        if(axis_user) begin
            if(frames!=0 && pixels!=307200)$fatal(1,"previous frame pixel count");
            frames++;pixels=0;frame_buffer=selected;
        end
        if(axis_data!==frame_buffer*307200+pixels+1)
            $fatal(1,"pixel %0d frame=%0d got=%0d expected=%0d",pixels,frames,axis_data,frame_buffer*307200+pixels+1);
        if(axis_last!=(pixels%640==639)) $fatal(1,"pipeline line marker");
        pixels++;verified++;
        if(frames==1 && pixels==150000) begin
            if(source_ack!=commit)$fatal(1,"old source descriptor not acknowledged");
            source_buffer=1;source_scene=1;source_sequence=2;commit=~commit;
        end
        if(frames==2 && pixels==307200) begin
            if(events!=2 || frame_buffer!=1)$fatal(1,"frame switch count");
            $display("PASS tb_frame_pipeline verified_pixels=%0d frames=%0d scene_events=%0d",verified,frames,events);
            $finish;
        end
    end
end
initial begin
    repeat(10)@(negedge clk);rst=0;
    repeat(100)@(negedge clk);source_valid=1;source_sequence=1;commit=1;
end
initial begin #100000000;$fatal(1,"frame pipeline timeout");end
endmodule
