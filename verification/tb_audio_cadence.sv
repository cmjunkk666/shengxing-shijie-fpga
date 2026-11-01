
`timescale 1ns/1ps
module tb_audio_cadence;
reg clk=0,rst=1,frame=0;
reg [31:0] count=0;
wire fault;
always #5 clk=~clk;
audio_cadence_monitor dut(.clk(clk),.rst(rst),.frame_start(frame),
 .sample_count(count),.cadence_fault(fault));
task boundary(input reg[31:0] value);
 @(negedge clk);count=value;frame=1;
 @(negedge clk);frame=0;
endtask
initial begin
 repeat(3)@(negedge clk);rst=0;
 boundary(32'hfffffc00);
 boundary(32'hfffffc00+806);
 boundary(32'hfffffc00+806+807);
 boundary(32'hfffffc00+806+807+806);
 if(fault)$fatal(1,"nominal cadence / counter wrap");
 boundary(count+805);if(!fault)$fatal(1,"missing sample not detected");
 boundary(count+807);if(!fault)$fatal(1,"fault not sticky");
 rst=1;repeat(2)@(negedge clk);rst=0;
 boundary(0);boundary(808);if(!fault)$fatal(1,"extra sample not detected");
 $display("PASS tb_audio_cadence normal_806_807 wrap missing extra sticky reset");$finish;
end
endmodule
