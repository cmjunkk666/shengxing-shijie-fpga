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
 localparam IDLE=0, INIT=1, ISSUE=2, CAPTURE=3, REPLAY=4, COMPLETE=5, FETCH=6;
 reg [2:0] state;
 reg init_go,read_go,initialized;
 reg [31:0] req_lba;
 reg [1:0] retries;
 reg [9:0] captured;
 reg capture_bad;
 reg [8:0] replay_index;
 reg [7:0] mem[0:511];
 reg [7:0] replay_data;
 always @(posedge clk) if(state==FETCH) replay_data<=mem[replay_index];
 wire init_busy_i,init_done_i,init_ready_i,high_capacity;
 wire [7:0] init_error_i;
 wire ic,ik,im,rc,rk,rm;
 wire reader_busy,reader_done,reader_valid;
 wire [7:0] reader_data,reader_error;
 wire [8:0] reader_index;
 wire init_owner=state==INIT;
 assign SD_nCS=init_owner?ic:rc;
 assign SD_DCLK=init_owner?ik:rk;
 assign SD_MOSI=init_owner?im:rm;
 assign busy=state!=IDLE;
 assign card_ready=initialized;
 assign valid=state==REPLAY;
 assign data=replay_data;
 assign index=replay_index;
 // Initialization clock <=400 kHz. Read divider denotes each half SPI period.
 sd_spi_init #(.SPI_CLK_DIV((CLK_HZ+799999)/800000),
   .POWER_UP_BYTES(10),.MAX_ACMD41_ATTEMPTS(4096),
   .STARTUP_DELAY_CYCLES(INIT_DELAY_CYCLES)) u_init(
   .clk(clk),.rst_n(!rst),.init_start(init_go),.init_busy(init_busy_i),
   .init_done(init_done_i),.init_ready(init_ready_i),.error_code(init_error_i),
   .card_high_capacity(high_capacity),.ocr(),.last_cmd(),.last_r1(),.acmd41_attempts(),
   .sd_cs_n(ic),.sd_sclk(ik),.sd_mosi(im),.sd_miso(SD_MISO));
 sd_spi_sector_reader #(.SPI_CLK_DIV(READ_DIV),
   .MAX_TOKEN_BYTES(((CLK_HZ/1000)*250)/(16*READ_DIV)),.CHECK_DATA_CRC(1)) u_reader(
   .clk(clk),.rst_n(!rst && !init_owner),.init_ready(initialized),
   .card_high_capacity(high_capacity),.sector_req(read_go),.sector_lba(req_lba),
   .sector_busy(reader_busy),.sector_done(reader_done),.sector_valid(reader_valid),
   .sector_byte(reader_data),.sector_byte_index(reader_index),.sector_error(reader_error),
   .last_r1(),.sd_cs_n(rc),.sd_sclk(rk),.sd_mosi(rm),.sd_miso(SD_MISO));
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   state<=IDLE;init_go<=0;read_go<=0;initialized<=0;init_done<=0;init_error<=0;
   req_lba<=0;retries<=0;captured<=0;capture_bad<=0;replay_index<=0;
   done<=0;error<=0;retry_count<=0;last_error_lba<=0;
  end else begin
   init_go<=0;read_go<=0;done<=0;init_done<=0;
   case(state)
    IDLE: if(init_start) begin initialized<=0;init_error<=0;init_go<=1;state<=INIT;end
     else if(req) begin
      req_lba<=lba;error<=0;retries<=0;
      if(initialized && !high_capacity && |lba[31:23]) begin error<=8'h07;last_error_lba<=lba;state<=COMPLETE;end
      else if(initialized) state<=ISSUE;
      else begin error<=8'h06;state<=COMPLETE;end
     end
    INIT: if(init_done_i) begin
     initialized<=init_ready_i && init_error_i==0;init_error<=init_error_i;
     init_done<=1;state<=IDLE;
    end
    ISSUE: if(!reader_busy) begin
     read_go<=1;captured<=0;capture_bad<=0;state<=CAPTURE;
    end
    CAPTURE: begin
     if(reader_valid) begin
      if(captured<512 && reader_index==captured[8:0]) mem[reader_index]<=reader_data;
      else capture_bad<=1;
      if(captured<513) captured<=captured+1'b1;
     end
     if(reader_done) begin
      if(reader_error!=0 || capture_bad || captured!=512) begin
       last_error_lba<=req_lba;
       if(retries<MAX_RETRIES) begin
        retries<=retries+1'b1;state<=ISSUE;
        if(retry_count!=16'hffff) retry_count<=retry_count+1'b1;
       end else begin error<=reader_error!=0?reader_error:8'he1;state<=COMPLETE;end
      end else begin replay_index<=0;state<=FETCH;end
     end
    end
    FETCH: state<=REPLAY;
    REPLAY: if(byte_ready) begin
     if(replay_index==511) state<=COMPLETE;
     else begin replay_index<=replay_index+1'b1;state<=FETCH;end
    end
    COMPLETE: begin done<=1;state<=IDLE;end
    default: state<=IDLE;
   endcase
  end
 end
endmodule
