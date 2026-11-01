
module sd_card_top
#(
	parameter  SPI_LOW_SPEED_DIV = 248,         // SD card low speed mode frequency division parameter,spi clk speed = clk speed /((SPI_LOW_SPEED_DIV + 2) * 2 )
	parameter  SPI_HIGH_SPEED_DIV = 0           // SD card high speed mode frequency division parameter,spi clk speed = clk speed /((SPI_HIGH_SPEED_DIV + 2) * 2 )
)
(
	input            clk,
	input            rst,
	output           SD_nCS,                    //SD card chip select (SPI mode)
	output           SD_DCLK,                   //SD card clock
	output           SD_MOSI,                   //SD card controller data output
	input            SD_MISO,                   //SD card controller data input
	output           sd_init_done,              //SD card initialization is complete
	input            sd_sec_read,               //SD card sector read
	input[31:0]      sd_sec_read_addr,          //SD card sector read address
	output[7:0]      sd_sec_read_data,          //SD card sector read data
	output           sd_sec_read_data_valid,    //SD card sector read data valid
	output           sd_sec_read_end,           //SD card sector read end
	input            sd_sec_write,              //SD card sector write
	input[31:0]      sd_sec_write_addr,         //SD card sector write address
	input[7:0]       sd_sec_write_data,         //SD card sector write data
	output           sd_sec_write_data_req,     //SD card sector write data next clock is valid
	output           sd_sec_write_end           //SD card sector write end
);

assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;
assign sd_init_done=!rst;
assign sd_sec_write_data_req=0;assign sd_sec_write_end=0;
reg [7:0] model_data=0;
reg model_valid=0,model_end=0;
assign sd_sec_read_data=model_data;
assign sd_sec_read_data_valid=model_valid;
assign sd_sec_read_end=model_end;
integer age=0,offset=0;
reg busy=0,blocked=0,corrupt=0,corrupt_next=0,corrupt_all=0;
reg [31:0] sector;
function [7:0] octet(input [31:0] sec,input integer off);
 begin
 octet=8'h55;
 if(sec==0 || sec==2)begin
 case(off)
 0:octet=8'h42;1:octet=8'h4d;
 2:octet=8'h36;3:octet=8'h03;4,5:octet=0; // 822 bytes = 54+128*2*3
 10:octet=54;11,12,13:octet=0;
 18:octet=128;19,20,21:octet=0;
 22:octet=2;23,24,25:octet=0;
 28:octet=24;29,30,31,32,33:octet=0;
 default:octet=8'h55;
 endcase
 end
 end
endfunction
always @(posedge clk or posedge rst)begin
 if(rst)begin age<=0;offset<=0;busy<=0;blocked<=0;model_valid<=0;model_end<=0;end
 else begin
 model_valid<=0;model_end<=0;
 if(!sd_sec_read)blocked<=0;
 if(!busy && !blocked && sd_sec_read)begin
  busy<=1;blocked<=1;age<=0;offset<=0;sector<=sd_sec_read_addr;
  corrupt<=corrupt_next || corrupt_all;corrupt_next<=0;
 end else if(busy)begin
  if(age==3)begin
   age<=0;
   if(offset<512)begin
    model_valid<=1;model_data<=(corrupt && offset==0)?8'h00:octet(sector,offset);
    offset<=offset+1;
   end else begin model_end<=1;busy<=0;end
  end else age<=age+1;
 end
 end
end
endmodule
