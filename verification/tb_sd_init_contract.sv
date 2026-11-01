`timescale 1ns/1ps
module tb_sd_init_contract;
reg clk=0,rst=1,ack=0;
always #5 clk=~clk;
wire initialized,req;
wire [47:0] cmd;
wire [15:0] divider;
sd_card_sec_read_write #(.SPI_LOW_SPEED_DIV(248),.SPI_HIGH_SPEED_DIV(2)) dut(
 .clk(clk),.rst(rst),.sd_init_done(initialized),.sd_sec_read(1'b0),.sd_sec_read_addr(32'd0),
 .sd_sec_read_data(),.sd_sec_read_data_valid(),.sd_sec_read_end(),
 .sd_sec_write(1'b0),.sd_sec_write_addr(32'd0),.sd_sec_write_data(8'd0),
 .sd_sec_write_data_req(),.sd_sec_write_end(),.spi_clk_div(divider),
 .cmd_req(req),.cmd_req_ack(ack),.cmd_req_error(1'b0),.cmd(cmd),.cmd_r1(),.cmd_data_len(),
 .block_read_req(),.block_read_valid(1'b0),.block_read_data(8'd0),.block_read_req_ack(1'b0),
 .block_write_req(),.block_write_data(),.block_write_data_rd(1'b0),.block_write_req_ack(1'b0));
task respond(input integer expected);
 begin
 wait(req && cmd[47:40]==expected);@(negedge clk);
 if(initialized || divider!=248)$fatal(1,"card marked ready before CMD16");
 ack=1;@(negedge clk);ack=0;repeat(2)@(negedge clk);
 end
endtask
integer i;
initial begin
 repeat(4)@(negedge clk);rst=0;
 respond(0);respond(8);respond(55);respond(41);
 wait(req && cmd[47:40]==16);
 repeat(20)begin @(negedge clk);if(initialized)$fatal(1,"early init while CMD16 waiting");end
 respond(16);
 repeat(20)begin @(negedge clk);if(!initialized || divider!=2)$fatal(1,"idle overwrote configured SPI speed");end
 rst=1;@(negedge clk);if(initialized)$fatal(1,"reset flag");
 $display("PASS tb_sd_init_contract early-ready guard and selected divider retained");
 $finish;
end
initial begin #100000;$fatal(1,"init timeout");end
endmodule
