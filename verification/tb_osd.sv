`timescale 1ns/1ps
module tb_osd;
 reg clk=0,rst=1,de=0,vs=0,present=0,scanned=0,aut=0;always #20 clk=~clk;
 reg [23:0] rgb=0;reg [1:0] scene=0;reg [3:0] ready=0,failed=0,found=0;reg [7:0] err=0;
 wire [23:0] pixel;
 player_osd dut(.clk(clk),.rst(rst),.de(de),.vs(vs),.rgb(rgb),.display_valid(present),.scan_complete(scanned),.auto_enabled(aut),
 .scene(scene),.period_seconds(4'd3),.ready_mask(ready),.failed_mask(failed),.found_mask(found),.error_code(err),.out_rgb(pixel));
 integer file,row,col,lit;
 task render(input reg [255:0] filename);
  begin
   repeat(5)@(negedge clk);vs=1;repeat(4)@(negedge clk);vs=0;repeat(4)@(negedge clk);
   file=$fopen(filename,"wb");$fwrite(file,"P6\n640 480\n255\n");lit=0;
   for(row=0;row<480;row++)begin
    for(col=0;col<640;col++)begin
     @(negedge clk);de=1;rgb=present?{8'(30+col/4),8'(35+row/3),8'd70}:24'd0;
     @(posedge clk);
     $fwrite(file,"%c%c%c",pixel[23:16],pixel[15:8],pixel[7:0]);
     if(pixel!=rgb)lit++;
     if((row>=72 || col>=328) && pixel!==rgb)$fatal(1,"OSD corrupts image outside status area");
    end
    @(negedge clk);de=0;repeat(12)@(negedge clk);
   end
   $fclose(file);if(lit<100)$fatal(1,"OSD text missing");
  end
 endtask
 initial begin
  repeat(5)@(negedge clk);rst=0;render("osd_boot.ppm");
  present=1;scanned=1;aut=1;scene=3;ready=4'b1011;failed=4'b0100;found=15;err=8'h50;render("osd_ready.ppm");
  $display("PASS tb_osd boot/cache/error overlay and unmodified pixels outside OSD");$finish;
 end
endmodule
