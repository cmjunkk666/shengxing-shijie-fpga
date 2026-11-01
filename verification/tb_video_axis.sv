`timescale 1ns/1ps
module tb_video_axis;
reg clk=0,rst=1,vs=0,de=0;
reg [23:0] rgb=0;
always #5 clk=~clk;
wire user,valid,last;
wire [23:0] data;
video_rgb_to_axis_640x480 dut(.I_clk(clk),.I_rst(rst),.I_vs(vs),.I_de(de),.I_rgb(rgb),
 .O_video_user(user),.O_video_valid(valid),.O_video_last(last),.O_video_data(data));
integer x,y,users=0,lasts=0,pixels=0;
initial begin
    repeat(3)@(negedge clk);rst=0;vs=1;
    repeat(4)@(negedge clk);vs=0;
    repeat(4)@(negedge clk);
    for(y=0;y<480;y++) begin
        for(x=0;x<640;x++) begin
            de=1;rgb=y*640+x;
            @(negedge clk);
            if(!valid || data!=y*640+x || last!=(x==639) || user!=(x==0 && y==0))
                $fatal(1,"AXIS marker/data at x=%0d y=%0d",x,y);
            pixels++;if(user)users++;if(last)lasts++;
        end
        de=0;repeat(160)@(negedge clk);
        if(valid || user || last) $fatal(1,"blanking valid");
    end
    $display("PASS tb_video_axis pixels=%0d lines=%0d frames=%0d",pixels,lasts,users);$finish;
end
endmodule
