`timescale 1ns/1ps
module tb_writer_abort;
 reg mc=0,wc=0,rst=1,req=0,abort_req=0,we=0;always #12.5 mc=~mc;always #5 wc=~wc;
 wire ack,abort_ack,done,wen;wire [20:0] wa;wire [31:0] wd;reg [31:0] din=0;
 integer busy_hold=0;wire busy=busy_hold!=0;
 always @(posedge mc) if(rst)busy_hold<=0;else if(wen)busy_hold<=12;else if(busy_hold>0)busy_hold<=busy_hold-1;
 frame_read_write #(.BURST_SIZE(256),.WRITE_V_FLIP(0),.FRAME_WIDTH(256),.FRAME_HEIGHT(2)) dut(
 .mem_clk(mc),.rst(rst),.Sdr_init_done(1'b1),.Sdr_init_ref_vld(1'b0),.Sdr_busy(busy),
 .App_rd_en(),.App_rd_addr(),.Sdr_rd_en(1'b0),.Sdr_rd_dout(32'd0),.read_clk(wc),.read_req(1'b0),.read_req_ack(),
 .read_adopt_toggle(),.read_adopt_buffer(),.read_fifo_empty(),.read_finish(),
 .read_addr_0(21'd0),.read_addr_1(21'd0),.read_addr_2(21'd0),.read_addr_3(21'd0),.read_addr_index(2'd0),.read_len(21'd512),.read_en(1'b0),.read_data(),
 .App_wr_en(wen),.App_wr_addr(wa),.App_wr_din(wd),.App_wr_dm(),.write_clk(wc),.write_req(req),.write_req_ack(ack),
 .write_abort(abort_req),.write_abort_ack(abort_ack),.write_finish(done),
 .write_addr_0(21'd0),.write_addr_1(21'd0),.write_addr_2(21'd0),.write_addr_3(21'd0),.write_addr_index(2'd0),.write_len(21'd512),.write_en(we),.write_data(din));
 integer written=0,done_count=0;reg verify=0;
 always @(posedge mc)if(!rst)begin
  if(wen)begin
   if(dut.write_fifo_aclr)$fatal(1,"FIFO cleared inside burst");
   if(verify && (wa!=written || wd!=32'ha5000000+written))$fatal(1,"stale data after abort wa=%0d data=%h",wa,wd);
   written++;
  end
  if(done)done_count++;
  if(abort_ack && (busy || wen))$fatal(1,"abort acknowledged before memory drained");
 end
 task start;
  begin @(negedge wc);req=1;wait(ack);@(negedge wc);req=0;wait(!ack);repeat(8)@(negedge wc);written=0;end
 endtask
 task push(input integer n);
  integer j;begin for(j=0;j<n;j++)begin @(negedge wc);we=1;din=32'ha5000000+j;@(negedge wc);we=0;repeat(2)@(negedge wc);end end
 endtask
 task abort_load;
  begin @(negedge wc);abort_req=1;wait(abort_ack);repeat(10)@(negedge wc);
   if(done_count!=0 || dut.rdusedw!=0)$fatal(1,"aborted frame completed or FIFO not empty");
   abort_req=0;wait(!abort_ack);repeat(10)@(negedge wc);
  end
 endtask
 initial begin
  repeat(10)@(negedge wc);rst=0;
  start;push(40);abort_load;if(written!=0)$fatal(1,"partial burst written");
  start;push(300);abort_load;if(written!=256)$fatal(1,"issued burst truncated %0d",written);
  verify=1;start;push(512);wait(done);repeat(10)@(negedge wc);
  if(written!=512 || done_count!=1)$fatal(1,"retry failed");
  $display("PASS tb_writer_abort incomplete FIFO, in-flight burst drain, held ack, stale FIFO cleanup, complete retry");$finish;
 end
 initial begin #1000000;$fatal(1,"abort deadlock state=%0d used=%0d",dut.frame_fifo_write_m0.state,dut.rdusedw);end
endmodule
