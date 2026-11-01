// CRC-checked sector transactions. Failed attempts never reach the consumer.
module sd_sector_service #(
 parameter integer CLK_HZ=100000000, READ_DIV=4, INIT_DELAY_CYCLES=10000000,
 parameter integer MAX_RETRIES=2
)(
 input wire clk,rst,init_start, output reg init_done, output wire card_ready,
 output reg [7:0] init_error,
 input wire req, input wire [31:0] lba, input wire byte_ready,
 output wire busy, output wire valid, output wire [7:0] data,
 output wire [8:0] index, output wire done, output wire [7:0] error,
 output reg [15:0] retry_count, output reg [31:0] last_error_lba,
 output wire SD_nCS,SD_DCLK,SD_MOSI,input wire SD_MISO
);

 reg initialized;integer mode=0;initial if(!$value$plusargs("CASE=%d",mode))mode=0;
 assign card_ready=initialized;assign SD_nCS=1;assign SD_DCLK=0;assign SD_MOSI=1;
 integer requests;
 fat_image_model #(.GAP(2048)) image(.clk(clk),.rst(rst),.req(req),.lba(lba),.ready(byte_ready),.mode(mode),
  .busy(busy),.valid(valid),.data(data),.index(index),.done(done),.error(error),.requests(requests));
 always @(posedge clk)begin
  if(rst)begin initialized<=0;init_done<=0;init_error<=0;retry_count<=0;last_error_lba<=0;end
  else begin init_done<=0;
   if(init_start)begin initialized<=1;init_done<=1;init_error<=0;end
   if(done && error!=0)last_error_lba<=lba;
  end
 end
endmodule
