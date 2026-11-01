// Contrast before final brightness/fade: unity=128, range=0..256.
// Two registered stages; RGB, DE and VS have identical latency.
module video_rgb_contrast(
 input wire clk,rst,de,vs,input wire [23:0] rgb,input wire [8:0] contrast,
 output reg de_out,vs_out,output reg [23:0] rgb_out
);
 reg de1,vs1;
 // Keep every multiplier unsigned. TD 6.2 packed the old signed blue
 // product with the unsigned audio-volume product, sharing SIGNEDAMUX=0.
 // Negative blue differences then became positive and clipped to 255.
 // floor((pixel-128)*C/128)+128 == floor(pixel*C/128)-C+128.
 // Delay C alongside the products so local adjustments remain aligned.
 reg [16:0] r_product,g_product,b_product;
 reg [8:0] contrast1;
 function [7:0] channel;input [16:0] value;input [8:0] gain;
 reg signed [10:0] adjusted;
 begin
  adjusted=$signed({1'b0,value[16:7]})-$signed({2'b0,gain})+11'sd128;
  channel=adjusted<0?8'd0:adjusted>255?8'd255:adjusted[7:0];
 end endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin de1<=0;vs1<=0;de_out<=0;vs_out<=0;rgb_out<=0;r_product<=0;g_product<=0;b_product<=0;contrast1<=0;end
  else begin
   r_product<=rgb[23:16]*contrast;
   g_product<=rgb[15:8]*contrast;
   b_product<=rgb[7:0]*contrast;
   contrast1<=contrast;
   de1<=de;vs1<=vs;de_out<=de1;vs_out<=vs1;
   rgb_out<={channel(r_product,contrast1),channel(g_product,contrast1),channel(b_product,contrast1)};
  end
 end
endmodule
