// RGB888 in/out. 256 means exact unity; zero means exact black.
module video_rgb_gain(
 input wire clk,rst,de,vs,input wire [23:0] rgb,
 input wire [8:0] fade_gain,brightness,
 output reg de_out,vs_out,output wire [23:0] rgb_out
);
 reg [17:0] combined;reg [16:0] red,green,blue;
 always @(posedge clk or posedge rst)begin
  if(rst)begin combined<=0;red<=0;green<=0;blue<=0;de_out<=0;vs_out<=0;end
  else begin
   combined<=fade_gain*brightness;
   red<=rgb[23:16]*combined[16:8];green<=rgb[15:8]*combined[16:8];blue<=rgb[7:0]*combined[16:8];
   de_out<=de;vs_out<=vs;
  end
 end
 assign rgb_out={red[15:8],green[15:8],blue[15:8]};
endmodule
