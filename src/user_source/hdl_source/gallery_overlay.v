// Gallery pixels come from the SDRAM address mapper; only OSD is generated here.
// Focus/ready flags are sampled once per frame. Invalid slots never expose RAM.
module gallery_overlay(
 input wire clk,rst,de,vs,enable,input wire [23:0] rgb,
 input wire [1:0] focus,input wire [3:0] ready_mask,failed_mask,
 output reg [23:0] out_rgb
);
 reg [9:0] x;reg [8:0] y;reg de_old,vs_old,active;
 (* async_reg="true" *) reg [9:0] status0,status1;
 reg [9:0] status;
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=0;de_old<=0;vs_old<=0;active<=0;status0<=0;status1<=0;status<=0;end
  else begin
   status0<={focus,ready_mask,failed_mask};status1<=status0;de_old<=de;vs_old<=vs;
   if(vs && !vs_old)begin y<=0;active<=enable;status<=status1;end
   else if(de_old && !de)y<=y+1'b1;
   if(de)x<=x+1'b1;else x<=0;
  end
 end
 function [34:0] glyph;input [7:0] c;begin case(c)
  8'd48:glyph=35'b01110100011001110101110011000101110;
  8'd49:glyph=35'b00100011000010000100001000010001110;
  8'd50:glyph=35'b01110100010000100010001000100011111;
  8'd51:glyph=35'b11110000010000101110000010000111110;
  8'd52:glyph=35'b00010001100101010010111110001000010;
  8'd53:glyph=35'b11111100001000011110000010000111110;
  8'd54:glyph=35'b01110100001000011110100011000101110;
  8'd55:glyph=35'b11111000010001000100010000100001000;
  8'd56:glyph=35'b01110100011000101110100011000101110;
  8'd57:glyph=35'b01110100011000101111000010000101110;
  8'd65:glyph=35'b01110100011000111111100011000110001;
  8'd66:glyph=35'b11110100011000111110100011000111110;
  8'd67:glyph=35'b01111100001000010000100001000001111;
  8'd68:glyph=35'b11110100011000110001100011000111110;
  8'd69:glyph=35'b11111100001000011110100001000011111;
  8'd70:glyph=35'b11111100001000011110100001000010000;
  8'd71:glyph=35'b01111100001000010111100011000101111;
  8'd72:glyph=35'b10001100011000111111100011000110001;
  8'd73:glyph=35'b01110001000010000100001000010001110;
  8'd76:glyph=35'b10000100001000010000100001000011111;
  8'd77:glyph=35'b10001110111010110101100011000110001;
  8'd78:glyph=35'b10001110011010110011100011000110001;
  8'd79:glyph=35'b01110100011000110001100011000101110;
  8'd80:glyph=35'b11110100011000111110100001000010000;
  8'd82:glyph=35'b11110100011000111110101001001010001;
  8'd83:glyph=35'b01111100001000001110000010000111110;
  8'd84:glyph=35'b11111001000010000100001000010000100;
  8'd85:glyph=35'b10001100011000110001100011000101110;
  8'd86:glyph=35'b10001100011000110001100010101000100;
  8'd47:glyph=35'b00001000010001000100010001000010000;
  8'd58:glyph=35'b00000001000010000000001000010000000;
  8'd46:glyph=35'b00000000000000000000000000011000110;
  8'd75:glyph=35'b10001100101010011000101001001010001;
  8'd87:glyph=35'b10001100011000110101101011010101010;
  8'd88:glyph=35'b10001100010101000100010101000110001;
  8'd89:glyph=35'b10001100010101000100001000010000100;
  default:glyph=0;
 endcase end endfunction

 function [7:0] textchar;input [319:0] s;input [5:0] n;
 begin textchar=s>>((39-n)*8);end endfunction
 wire [1:0] tile={y>=240,x>=320};
 wire [9:0] tx=x>=320?x-10'd320:x;
 wire [8:0] ty=y>=240?y-9'd240:y;
 reg [7:0] ch;reg [34:0] bitmap;reg [9:0] lx;reg [8:0] ly;reg text_zone;
 reg [23:0] fg;
 always @*begin
  out_rgb=rgb;ch=32;bitmap=0;lx=0;ly=0;text_zone=0;fg=24'he8f2ff;
  if(active && de)begin
   if(!status[4+tile])out_rgb=status[tile]?24'h38242a:24'h18222e;
   if(tx<4 || tx>=316 || ty<4 || ty>=236)
    out_rgb=tile==status[9:8]?24'hffd060:24'h506070;
   if(y>=8 && y<40 && x>=8 && x<632)begin
    text_zone=1;lx=x-8;ly=y<24?y-8:y-24;
    ch=textchar(y<24?"GALLERY  K1 NEXT  HOLD K1 PREVIOUS      ":
                              "K2 OPEN  HOLD K2 BACK                   ",lx[9:4]);
   end else if(ty>=212 && ty<228 && tx>=8 && tx<312)begin
    text_zone=1;lx=tx-8;ly=ty-212;
    ch=textchar(status[4+tile]?"PIC 1  READY                            ":
                status[tile]?"PIC 1  ERROR                            ":
                             "PIC 1  WAIT                             ",lx[9:4]);
    if(lx[9:4]==4)ch="1"+tile;
   end
   if(text_zone)begin
    out_rgb=24'h101b28;bitmap=glyph(ch);
    if(lx[3:1]<5 && ly[3:1]<7 && bitmap[34-ly[3:1]*5-lx[3:1]])out_rgb=fg;
   end
  end
 end
endmodule
