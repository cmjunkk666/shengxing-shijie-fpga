`timescale 1ns/1ps
module spi_card_model(
 input wire cs,sclk,mosi,input integer fault_mode,input wire legacy,
 output reg miso=1,output integer reads=0,output integer cmd16_count=0
);
 reg [47:0] command=0;reg [7:0] rx=0,tx=255;integer bits=0,command_bytes=0;
 reg [7:0] queue[0:1039];integer head=0,tail=0;reg initialized=0;
 integer i;reg [7:0] value;reg [31:0] argument;reg [15:0] crc;
 function automatic [15:0] crc_byte(input [15:0] old,input [7:0] d);
  reg [15:0] c;integer k;begin c=old^(16'(d)<<8);
   for(k=0;k<8;k++)c=c[15]?(c<<1)^16'h1021:c<<1;
   crc_byte=c;
  end
 endfunction
 task push(input [7:0] d);begin queue[tail]=d;tail++;end endtask
 always @(posedge cs)begin bits=0;command_bytes=0;head=0;tail=0;tx=255;miso=1;end
 always @(posedge sclk)if(!cs)begin
  rx={rx[6:0],mosi};
  if(bits==7)begin
   bits=0;
   if(command_bytes!=0 || rx[7:6]==2'b01)begin
    command={command[39:0],rx};command_bytes++;
    if(command_bytes==6)begin
     command_bytes=0;argument=command[39:8];
     case(command[45:40])
      0:begin initialized=0;push(1);end
      8:if(legacy)push(5);else begin push(1);push(0);push(0);push(1);push(8'haa);end
      55:push(initialized?0:1);
      41:begin initialized=1;push(0);end
      58:begin push(0);push(legacy?8'h80:8'hc0);push(8'hff);push(8'h80);push(0);end
      16:begin if(argument!=512)$fatal(1,"CMD16 incorrect block length");cmd16_count++;push(0);end
      17:begin
       reads++;
       if(legacy && argument[8:0]!=0)$fatal(1,"SDSC requires byte address");
       if(legacy)argument=argument>>9;
       if(fault_mode!=3)begin
        push(0);
        if(fault_mode!=4)begin
         push(255);push(8'hfe);crc=0;
         for(i=0;i<512;i++)begin value=argument+i;push(value);crc=crc_byte(crc,value);end
         if(fault_mode==2 || (fault_mode==1 && reads==1))crc=crc^1;
         push(crc[15:8]);push(crc[7:0]);
        end
       end
      end
      default:push(4);
     endcase
    end
   end
  end else bits++;
 end
 always @(negedge sclk)if(!cs)begin
  if(bits==0)begin if(head<tail)begin tx=queue[head];head++;end else tx=255;end
  miso=tx[7-bits];
 end
endmodule
module tb_sd_service;
 reg clk=0,rst=1,init=0,req=0,ready=1,legacy=0;integer fault=0;
 always #500 clk=~clk;
 reg [31:0] lba=7;wire idone,card,busy,valid,done,cs,sc,mo,mi;wire [7:0] ie,data,error;
 wire [8:0] index;wire [15:0] retries;wire [31:0] bad_lba;integer reads,cmd16s;
 sd_sector_service #(.CLK_HZ(1000000),.READ_DIV(1),.INIT_DELAY_CYCLES(10)) dut(
 .clk(clk),.rst(rst),.init_start(init),.init_done(idone),.card_ready(card),.init_error(ie),
 .req(req),.lba(lba),.byte_ready(ready),.busy(busy),.valid(valid),.data(data),.index(index),
 .done(done),.error(error),.retry_count(retries),.last_error_lba(bad_lba),
 .SD_nCS(cs),.SD_DCLK(sc),.SD_MOSI(mo),.SD_MISO(mi));
 spi_card_model sd(.cs(cs),.sclk(sc),.mosi(mo),.fault_mode(fault),.legacy(legacy),.miso(mi),.reads(reads),.cmd16_count(cmd16s));
 integer received=0,oldreads=0,t=0;reg [7:0] expected;
 always @(posedge clk)if(!rst && valid && ready)begin
  expected=lba+received;
  if(index!=received || data!==expected)$fatal(1,"replay order/content %0d %0d %h",index,received,data);
  received++;
 end
 time last_edge=0;
 always @(sc)if(!rst && dut.init_owner)begin
  if(last_edge!=0 && $time-last_edge<2000)$fatal(1,"init SPI exceeds 400kHz");last_edge=$time;
 end
 task initialize(input bit old_card);
  begin @(negedge clk);rst=1;legacy=old_card;req=0;init=0;last_edge=0;
   repeat(5)@(negedge clk);rst=0;init=1;@(negedge clk);init=0;
   wait(idone);@(negedge clk);if(!card || ie!=0)$fatal(1,"init failed %h",ie);
  end
 endtask
 task read_sector(input integer f,input bit good);
  begin fault=f;received=0;oldreads=reads;
   @(negedge clk);req=1;@(negedge clk);req=0;
   // Exercise consumer backpressure across the replay stage.
   while(!done)begin @(negedge clk);t++;ready=(t%7!=0);end
   ready=1;
   if(good && (error!=0 || received!=512))$fatal(1,"good sector error=%h received=%0d",error,received);
   if(!good && (error==0 || received!=0 || reads-oldreads!=3))$fatal(1,"failed sector leaked/failed retries error=%h received=%0d reads=%0d",error,received,reads-oldreads);
   @(negedge clk);
  end
 endtask
 initial begin
  initialize(0);read_sector(1,1);
  if(retries!=1 || reads!=2)$fatal(1,"CRC retry missing");
  read_sector(2,0);read_sector(3,0);read_sector(4,0);read_sector(0,1);
  initialize(1);if(cmd16s==0)$fatal(1,"SDSC missing CMD16");read_sector(0,1);
  $display("PASS tb_sd_service SPI init speed, SDHC/SDSC, CRC/retry, R1/token timeout, no bad-byte leakage, replay backpressure, reinit");$finish;
 end
 initial begin #(64'd5000000000);$fatal(1,"SPI timeout state=%0d initstate=%0d",dut.state,dut.u_init.state);end
endmodule
