// TEST ONLY: protocol mocks; full data path tested separately.
// CRC-checked sector transactions. Failed attempts never reach the consumer.
module sd_sector_service #(
 parameter integer CLK_HZ=100000000, READ_DIV=4, INIT_DELAY_CYCLES=10000000,
 parameter integer MAX_RETRIES=2
)(
 input wire clk,rst,init_start, output reg init_done, output wire card_ready,
 output reg [7:0] init_error,
 input wire req, input wire [31:0] lba, input wire byte_ready,
 output wire busy, output wire valid, output wire [7:0] data,
 output wire [8:0] index, output reg done, output reg [7:0] error,
 output reg [15:0] retry_count, output reg [31:0] last_error_lba,
 output wire SD_nCS,SD_DCLK,SD_MOSI,input wire SD_MISO
);

 reg initialized;assign card_ready=initialized;assign busy=0;assign valid=0;assign data=0;assign index=0;
 assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;
 always @(posedge clk)if(rst)begin initialized<=0;init_done<=0;init_error<=0;done<=0;error<=0;retry_count<=0;last_error_lba<=0;end
 else begin init_done<=0;if(init_start)begin initialized<=1;init_done<=1;end end
endmodule
// Read-only FAT32, fixed short names in the root directory.
// One sector owner: the scanner yields between sectors to a requested file.
module fat32_media #(
 parameter integer MAX_ROOT_CLUSTERS=256,
 parameter integer MAX_FILE_BYTES=2097152
)(
 input wire clk,rst,start,scan_enable,
 output reg mounted,scan_done,output reg [7:0] fs_error,
 output reg [3:0] found_mask,
 input wire file_start,input wire [1:0] file_id,input wire cancel,
 output wire file_available,output reg file_busy,output reg file_done,
 output reg [7:0] file_error,output wire [31:0] file_size,
 output wire byte_valid,output wire [7:0] byte_data,input wire byte_ready,
 output reg sector_req,output reg [31:0] sector_lba,
 input wire sector_busy,sector_valid,input wire [7:0] sector_data,
 input wire [8:0] sector_index,input wire sector_done,input wire [7:0] sector_error,
 output wire sector_ready
);

 integer count;integer mode=0;initial if(!$value$plusargs("CASE=%d",mode))mode=0;
 assign file_available=mounted&&!file_busy;assign file_size=256;assign byte_valid=0;assign byte_data=0;assign sector_ready=1;
 always @(posedge clk)if(rst)begin mounted<=0;scan_done<=0;fs_error<=0;found_mask<=0;file_busy<=0;file_done<=0;file_error<=0;sector_req<=0;sector_lba<=0;count<=0;end
 else begin
  file_done<=0;
  if(start)begin mounted<=1;scan_done<=1;found_mask<=4'b1011;end
  if(file_start)begin file_busy<=1;file_error<=0;count<=0;end
  if(file_busy)begin count<=count+1;
   if(count==100 || cancel)begin file_done<=1;file_busy<=0;file_error<=(mode==1 && file_id==0)?8'h05:0;end
  end
 end
endmodule
// Strict 640x480 RGB888 BMP stream decoder; bottom-up rows are remapped by writer.
module bmp_stream_decoder(
 input wire clk,rst,start,input wire [31:0] file_size,
 input wire byte_valid,input wire [7:0] byte_data,input wire file_done,
 output reg pixel_valid,output reg [23:0] pixel_data,
 output reg done,output reg [7:0] error,output wire cancel,
 output reg [18:0] pixel_count
);

 assign cancel=0;
 always @(posedge clk)if(rst)begin done<=0;error<=0;pixel_valid<=0;pixel_data<=0;pixel_count<=0;end
 else begin done<=file_done;pixel_valid<=0;if(file_done)pixel_count<=307200;end
endmodule
