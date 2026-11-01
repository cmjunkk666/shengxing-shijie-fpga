`timescale 1ns/1ps
module tb_fat32_media;
 reg clk=0,rst=1,start=0,scan=0,go=0,cancel_req=0;reg [1:0] id=0;integer mode=0;
 always #5 clk=~clk;
 wire dc; wire mounted,scanned,available,fb,fd,bv,req,busy,sv,sd,ready;
 wire [7:0] fe,err,bd,sdata,se;wire [3:0] found;wire [31:0] size,lba;wire [8:0] si;
 integer requests;
 fat32_media #(.MAX_ROOT_CLUSTERS(8)) dut(.clk(clk),.rst(rst),.start(start),.scan_enable(scan),
 .mounted(mounted),.scan_done(scanned),.fs_error(fe),.found_mask(found),
 .file_start(go),.file_id(id),.cancel(cancel_req|dc),.file_available(available),.file_busy(fb),.file_done(fd),
 .file_error(err),.file_size(size),.byte_valid(bv),.byte_data(bd),.byte_ready(1'b1),
 .sector_req(req),.sector_lba(lba),.sector_busy(busy),.sector_valid(sv),.sector_data(sdata),.sector_index(si),
 .sector_done(sd),.sector_error(se),.sector_ready(ready));
 fat_image_model card(.clk(clk),.rst(rst),.req(req),.lba(lba),.ready(ready),.mode(mode),
 .busy(busy),.valid(sv),.data(sdata),.index(si),.done(sd),.error(se),.requests(requests));
 wire pv,dd;wire [23:0] pd;wire [7:0] de;wire [18:0] pc;
 bmp_stream_decoder decoder(.clk(clk),.rst(rst),.start(go),.file_size(size),.byte_valid(bv),.byte_data(bd),
 .file_done(fd),.pixel_valid(pv),.pixel_data(pd),.done(dd),.error(de),.cancel(dc),.pixel_count(pc));
 integer pixels=0;reg [23:0] expected;
 always @(negedge clk) if(pv) begin
  expected={8'(id*40+17),8'(pixels/640),8'(pixels%640)};
  if(pd!==expected)$fatal(1,"pixel mismatch mode=%0d idx=%0d actual=%h expected=%h",mode,pixels,pd,expected);
  pixels++;
 end
 task reset_case(input integer m);
  begin @(negedge clk);rst=1;mode=m;scan=0;go=0;start=0;cancel_req=0;
   repeat(5)@(negedge clk);rst=0;start=1;@(negedge clk);start=0;
  end
 endtask
 task load_file(input integer n,input bit good);
  begin
   wait(available);@(negedge clk);id=n;pixels=0;go=1;@(negedge clk);go=0;
   wait(dd);@(negedge clk);
   if(good && (err!=0 || de!=0 || pixels!=307200))$fatal(1,"file %0d mode %0d error %h/%h pixels %0d",n,mode,err,de,pixels);
   if(!good && err==0 && de==0)$fatal(1,"bad file accepted mode %0d",mode);
   $display("file mode=%0d id=%0d pixels=%0d fs=%h bmp=%h",mode,n,pixels,err,de);
  end
 endtask
 integer m,j;
 initial begin
  for(m=0;m<=9;m++) begin
   reset_case(m);
   if(m==2)begin wait(scanned);if(fe==0 || mounted)$fatal(1,"invalid BPB mounted");end
   else if(m==4)begin wait(mounted);scan=1;wait(scanned);if(fe!=8'h33)$fatal(1,"root loop unbounded");end
   else begin
    wait(mounted);scan=1;wait(found[0]);scan=0;wait(available);
    if(scanned)$fatal(1,"first picture waited for directory completion");
    load_file(0,m==0 || m==1);
    if(m<=1)begin
     scan=1;wait(scanned);scan=0;
     if(found!==(m==1?4'b1011:4'b1111))$fatal(1,"directory/root chain/missing file scan %b",found);
     for(j=1;j<4;j++)if(found[j])load_file(j,1);
    end
   end
  end
  $display("PASS tb_fat32_media MBR/superfloppy, root sectors+clusters, fragmented files, partial directory, loops, CRC error, BMP rejection");$finish;
 end
 initial begin #300000000;$fatal(1,"FAT timeout mode=%0d state=%0d lba=%0d found=%b",mode,dut.state,lba,found);end
endmodule

