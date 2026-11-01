
`timescale 1ns/1ps
module tb_frame_writer;
reg clk=0,rst=1,req=0,feeding=0;
always #4 clk=~clk;
integer credits=0,produced=0,written=0,cycles=0;
reg [31:0] random_state=32'h20260914;
wire [9:0] words=credits;
wire read_busy=(cycles%127<17);
wire we,we_ref,ack,ack_ref,finish,finish_ref,clear_fifo,clear_ref,busy,busy_ref;
wire [20:0] addr,addr_ref;
frame_fifo_write #(.BURST_SIZE(256),.FRAME_WIDTH(640),.FRAME_HEIGHT(480),.WRITE_V_FLIP(1)) dut(
 .write_abort(1'b0),.write_abort_ack(),
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .App_rd_busy(read_busy),.O_wr_busy(busy),.App_wr_en(we),.App_wr_addr(addr),
 .write_req(req),.write_req_ack(ack),.write_finish(finish),
 .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(2'd1),.write_len(21'd307200),.fifo_aclr(clear_fifo),.rdusedw(words));
frame_fifo_write_reference #(.BURST_SIZE(256),.FRAME_WIDTH(640),.FRAME_HEIGHT(480),.WRITE_V_FLIP(1)) reference_dut(
 .rst(rst),.mem_clk(clk),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .App_rd_busy(read_busy),.O_wr_busy(busy_ref),.App_wr_en(we_ref),.App_wr_addr(addr_ref),
 .write_req(req),.write_req_ack(ack_ref),.write_finish(finish_ref),
 .write_addr_0(21'd0),.write_addr_1(21'd307200),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(2'd1),.write_len(21'd307200),.fifo_aclr(clear_ref),.rdusedw(words));
always @(negedge clk) if(!rst) begin
    if({we,ack,finish,clear_fifo,busy,addr}!=={we_ref,ack_ref,finish_ref,clear_ref,busy_ref,addr_ref})
        $fatal(1,"writer differs from original at cycle %0d",cycles);
    cycles++;
    random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
    if(clear_fifo) credits=0;
    else begin
        if(we) begin
            if(credits<=0)$fatal(1,"write FIFO underflow");
            if(addr != 307200+(479-written/640)*640+written%640)
                $fatal(1,"vertical write address %0d at pixel %0d",addr,written);
            credits--;written++;
        end
        if(feeding && credits<480 && produced<307200 && random_state[0]) begin credits++;produced++;end
    end
    if(finish) begin
        if(written!=307200 || credits!=0)$fatal(1,"frame write completion");
        $display("PASS tb_frame_writer pixels=%0d cycle_equivalence=%0d seed=20260914",written,cycles);$finish;
    end
end
initial begin
 repeat(5)@(negedge clk);rst=0;req=1;
 wait(ack);@(posedge clk);req=0;
 wait(!clear_fifo);@(posedge clk);feeding=1;
end
initial begin #30000000;$fatal(1,"writer timeout");end
endmodule
