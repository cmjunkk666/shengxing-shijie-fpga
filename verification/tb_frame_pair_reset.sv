`timescale 1ns/1ps
module tb_frame_pair_reset;
reg mc=0,wc=0,rc=0,rst=1,req=0,we=0;
always #4 mc=~mc;
always #5 wc=~wc;
always #20 rc=~rc;
reg [31:0] din=0;
wire ack,done,ren,wen;
wire [20:0] ra,wa;
wire [31:0] wd,outdata;
wire empty;
reg readreq=0,returned_valid=0;
wire readack;
integer j;
frame_read_write #(.BURST_SIZE(128),.WRITE_V_FLIP(0),.FRAME_WIDTH(128),.FRAME_HEIGHT(2)) dut(
 .write_abort(1'b0),.write_abort_ack(),
 .mem_clk(mc),.rst(rst),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(1'b0),
 .App_rd_en(ren),.App_rd_addr(ra),.Sdr_rd_en(returned_valid),.Sdr_rd_dout(32'd0),
 .read_clk(rc),.read_req(readreq),.read_req_ack(readack),.read_finish(),
 .read_adopt_toggle(),.read_adopt_buffer(),.read_fifo_empty(empty),
 .read_addr_0(21'd0),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),
 .read_addr_index(2'd0),.read_len(21'd256),.read_en(1'b0),.read_data(outdata),
 .App_wr_en(wen),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(),
 .write_clk(wc),.write_req(req),.write_req_ack(ack),.write_finish(done),
 .write_addr_0(21'd0),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),
 .write_addr_index(2'd0),.write_len(21'd256),.write_en(we),.write_data(din));
integer received=0;
reg verify=0;
always @(posedge mc)if(!rst && wen && verify)begin
 if(wa!=received || wd!=32'h10000000+received)$fatal(1,"FIFO data after reset addr=%0d word=%h expected=%0d",wa,wd,received);
 received=received+1;
end
task start;
 begin
 @(negedge wc);req=1;
 wait(ack);repeat(3)@(negedge wc);req=0;
 repeat(15)@(negedge wc);
 end
endtask
task push(input integer n);
 begin
 for(j=0;j<n;j++)begin
  @(negedge wc);we=1;din=32'h10000000+j;
  @(negedge wc);we=0;
  repeat(3)@(negedge wc);
 end
 end
endtask
initial begin
 repeat(6)@(negedge wc);rst=0;
 start;push(40);
 @(negedge mc);returned_valid=1;
 repeat(16)@(negedge mc);returned_valid=0;
 repeat(8)@(negedge rc);
 if(empty)$fatal(1,"read FIFO setup did not contain data");
 #2;rst=1;req=0;we=0;repeat(10)@(negedge wc);
 if(dut.rdusedw!==0 || !empty)$fatal(1,"global reset failed to empty FIFOs");
 rst=0;repeat(10)@(negedge wc);
 verify=1;start;push(256);wait(done);repeat(10)@(negedge wc);
 if(received!=256)$fatal(1,"missing words after reset %0d",received);
 $display("PASS tb_frame_pair_reset real write/read FIFOs reset and 256 ordered writes after aborted load");
 $finish;
end
initial begin #1000000;$fatal(1,"frame pair timeout req=%0b ack=%0b state=%0d received=%0d used=%0d count=%0d burst=%0d into=%b childused=%b len=%d readbusy=%b readerstate=%d",req,ack,dut.frame_fifo_write_m0.state,received,dut.rdusedw,dut.frame_fifo_write_m0.write_cnt,dut.frame_fifo_write_m0.burst_cnt, dut.frame_fifo_write_m0.into_burst, dut.frame_fifo_write_m0.rdusedw, dut.frame_fifo_write_m0.write_len_latch, dut.App_rd_busy, dut.frame_fifo_read_m0.state);end
endmodule
