`timescale 1ns/1ps
module tb_key_events;
reg clk=0, rst=1, k1=1, k2=1;
always #5 clk=~clk;
wire ne, pe, ae, ce, active;
integer nc=0, pc=0, ac=0, cc=0, checks=0;
key_events #(.CLK_FREQ_HZ(1000), .DEBOUNCE_MS(3), .LONG_PRESS_MS(12)) dut(
    .clk(clk),.rst(rst),.key1_n(k1),.key2_n(k2),
    .next_event(ne),.prev_event(pe),.toggle_auto_event(ae),
    .cycle_period_event(ce),.interaction_active(active));
always @(negedge clk) begin
    if (!rst) begin
        nc=nc+ne; pc=pc+pe; ac=ac+ae; cc=cc+ce;
        if ((ne+pe+ae+ce)>1) $fatal(1,"multiple events in one cycle");
    end
end
task step(input integer n); repeat(n) @(negedge clk); endtask
task expect_counts(input integer n,p,a,c,input string label_text);
    step(1);
    if(nc!=n || pc!=p || ac!=a || cc!=c)
        $fatal(1,"%s counts=%0d,%0d,%0d,%0d",label_text,nc,pc,ac,cc);
    checks=checks+1; $display("PASS %s",label_text);
endtask
initial begin
    step(3); rst=0; step(16);
    // Sub-debounce glitches must not become gestures.
    k1=0;step(1);k1=1;step(1);k1=0;step(1);k1=1;step(20);
    expect_counts(0,0,0,0,"bounce rejected");
    k1=0;step(8);expect_counts(0,0,0,0,"short waits for release");
    k1=1;step(12);expect_counts(1,0,0,0,"KEY1 short next");
    k2=0;step(8);k2=1;step(12);expect_counts(1,0,1,0,"KEY2 short auto");
    k2=0;step(60);expect_counts(1,1,1,0,"long previous once while held");
    k2=1;step(12);expect_counts(1,1,1,0,"long release has no short event");
    k1=0;step(60);k1=1;step(12);expect_counts(1,1,1,1,"KEY1 long period only");
    k1=0;k2=0;step(30);k1=1;step(25);k2=1;step(16);
    expect_counts(1,1,1,1,"overlap and staggered release suppressed");
    rst=1;k2=0;step(3);rst=0;step(40);k2=1;step(20);
    expect_counts(1,1,1,1,"held through reset ignored");
    k2=0;step(8);k2=1;step(12);expect_counts(1,1,2,1,"new gesture after reset accepted");
    // Hold duration is measured in debounced cycles. Test on either side of threshold.
    k1=0;wait(dut.stable[0]==0);@(negedge clk);step(6);k1=1;step(20);
    expect_counts(2,1,2,1,"release below long threshold");
    k1=0;step(25);k1=1;step(15);expect_counts(2,1,2,2,"release above threshold");
    $display("PASS tb_key_events checks=%0d",checks);$finish;
end
initial begin #100000; $fatal(1,"key test timeout"); end
endmodule
