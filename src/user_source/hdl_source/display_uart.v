// 25 MHz, 115200 baud, 8N1. Mid-bit sampling after a qualified start bit.
module display_uart_rx #(parameter integer DIVISOR=217)(
 input wire clk,rst,rx,output reg valid,framing_error,output reg [7:0] data
);
 (* async_reg="true" *) reg [2:0] rx_sync;
 reg [8:0] timer;reg [1:0] state;reg [2:0] bit_index;reg [7:0] shift;
 always @(posedge clk or posedge rst)
  if(rst)rx_sync<=3'b111;else rx_sync<={rx_sync[1:0],rx};
 always @(posedge clk or posedge rst)begin
  if(rst)begin timer<=0;state<=0;bit_index<=0;shift<=0;data<=0;valid<=0;framing_error<=0;end
  else begin
   valid<=0;framing_error<=0;
   case(state)
    0:if(!rx_sync[2])begin timer<=DIVISOR/2-1;state<=1;end
    1:if(timer!=0)timer<=timer-1'b1;
      else if(!rx_sync[2])begin timer<=DIVISOR-1;bit_index<=0;state<=2;end else state<=0;
    2:if(timer!=0)timer<=timer-1'b1;
      else begin shift[bit_index]<=rx_sync[2];timer<=DIVISOR-1;if(bit_index==7)state<=3;else bit_index<=bit_index+1'b1;end
    3:if(timer!=0)timer<=timer-1'b1;
      else begin state<=0;if(rx_sync[2])begin data<=shift;valid<=1;end else framing_error<=1;end
   endcase
  end
 end
endmodule
module display_uart_tx #(parameter integer DIVISOR=217)(
 input wire clk,rst,start,input wire [7:0] data,output wire tx,output reg busy
);
 reg [9:0] shift;reg [8:0] timer;reg [3:0] bit_index;
 assign tx=busy?shift[0]:1'b1;
 always @(posedge clk or posedge rst)begin
  if(rst)begin shift<=10'h3ff;timer<=0;bit_index<=0;busy<=0;end
  else if(!busy)begin
   if(start)begin shift<={1'b1,data,1'b0};timer<=DIVISOR-1;bit_index<=0;busy<=1;end
  end else if(timer!=0)timer<=timer-1'b1;
  else begin timer<=DIVISOR-1;shift<={1'b1,shift[9:1]};if(bit_index==9)busy<=0;else bit_index<=bit_index+1'b1;end
 end
endmodule
