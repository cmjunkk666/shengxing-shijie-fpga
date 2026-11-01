// 4096 PCM samples = 85.3 ms at 48 kHz. Source-registered Gray pointers
// include the wrap bit; RAM contents need no reset. Reset release is local.
module pcm_async_fifo #(parameter AW=12)(
 input wire wr_clk,rd_clk,arst,
 input wire wr_en,input wire [15:0] wr_data,output wire full,
 input wire rd_en,output reg [15:0] rd_data,output reg rd_valid,
 output wire empty,output wire [AW:0] rd_level
);
 wire wr_rst,rd_rst;
 reset_release_sync wr_reset(.clk(wr_clk),.arst(arst),.rst(wr_rst));
 reset_release_sync rd_reset(.clk(rd_clk),.arst(arst),.rst(rd_rst));
 reg [15:0] memory[0:(1<<AW)-1];
 reg [AW:0] wr_binary,wr_gray,rd_binary,rd_gray;
 (* async_reg="true" *) reg [AW:0] rd_gray_w0,rd_gray_w1,wr_gray_r0,wr_gray_r1;
 wire write_take=wr_en && !full && !wr_rst;
 wire read_take=rd_en && !empty && !rd_rst;
 wire [AW:0] wr_next=wr_binary+1'b1,rd_next=rd_binary+1'b1;
 assign full=wr_rst || wr_gray=={~rd_gray_w1[AW:AW-1],rd_gray_w1[AW-2:0]};
 assign empty=rd_rst || rd_gray==wr_gray_r1;
 function [AW:0] binary;input [AW:0] gray;integer i;
 begin binary[AW]=gray[AW];for(i=AW-1;i>=0;i=i-1)binary[i]=binary[i+1]^gray[i];end endfunction
 assign rd_level=binary(wr_gray_r1)-rd_binary;
 always @(posedge wr_clk) if(write_take) memory[wr_binary[AW-1:0]]<=wr_data;
 always @(posedge rd_clk) if(read_take) rd_data<=memory[rd_binary[AW-1:0]];
 always @(posedge wr_clk or posedge wr_rst)begin
  if(wr_rst)begin wr_binary<=0;wr_gray<=0;rd_gray_w0<=0;rd_gray_w1<=0;end
  else begin
   rd_gray_w0<=rd_gray;rd_gray_w1<=rd_gray_w0;
   if(write_take)begin wr_binary<=wr_next;wr_gray<=(wr_next>>1)^wr_next;end
  end
 end
 always @(posedge rd_clk or posedge rd_rst)begin
  if(rd_rst)begin rd_binary<=0;rd_gray<=0;wr_gray_r0<=0;wr_gray_r1<=0;rd_valid<=0;end
  else begin
   wr_gray_r0<=wr_gray;wr_gray_r1<=wr_gray_r0;rd_valid<=read_take;
   if(read_take)begin rd_binary<=rd_next;rd_gray<=(rd_next>>1)^rd_next;end
  end
 end
endmodule
