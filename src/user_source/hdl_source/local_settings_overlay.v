// Draw after brightness so settings remain usable even when brightness=0.
module local_settings_overlay(
 input wire clk,rst,de,vs,menu_active,input wire [2:0] menu_field,
 input wire [8:0] brightness,contrast,volume,input wire [1:0] wave_mode,input wire caption_enable,
 input wire [23:0] rgb,output reg [23:0] out_rgb
);
 reg [9:0] x;reg [8:0] y;reg de_old,vs_old;
 (* async_reg="true" *) reg [3:0] status0,status1;
 reg [3:0] status;
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=0;de_old<=0;vs_old<=0;status0<=0;status1<=0;status<=0;end
  else begin
   status0<={menu_active,menu_field};status1<=status0;de_old<=de;vs_old<=vs;
   if(vs && !vs_old)begin y<=0;status<=status1;end else if(de_old && !de)y<=y+1'b1;
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
  8'd43:glyph=35'b00000001000010011111001000010000000;
  8'd45:glyph=35'b00000000000000011111000000000000000;
  default:glyph=0;
 endcase end endfunction


 function [7:0] textchar;input [223:0] s;input [4:0] n;
 begin textchar=s>>((27-n)*8);end endfunction
 reg [7:0] ch;reg [34:0] bitmap;reg [9:0] lx;reg [8:0] ly;
 reg [2:0] row;reg [8:0] gain;reg text_zone;
 always @*begin
  out_rgb=rgb;ch=32;bitmap=0;lx=0;ly=0;row=0;gain=0;text_zone=0;
  if(status[3] && de && x>=80 && x<560 && y>=128 && y<420)begin
   out_rgb=24'h142235;
   if(x<83 || x>=557 || y<131 || y>=417)out_rgb=24'h60c8ff;
   if(y>=136 && y<152 && x>=96 && x<544)begin
    text_zone=1;lx=x-96;ly=y-136;ch=textchar("SETTINGS  TAP BOTH TO CLOSE ",lx[8:4]);
   end else if(y>=168 && y<360)begin
    ly=y-168;row=ly[7:5];lx=x-96;
    if(row==status[2:0] && x>=88 && x<552)out_rgb=24'h304862;
    if(x>=96 && x<288 && ly[4:0]<16)begin
     text_zone=1;
     case(row)
      0:ch=textchar("BRIGHTNESS                  ",lx[8:4]);
      1:ch=textchar("CONTRAST                    ",lx[8:4]);
      2:ch=textchar("VOLUME                      ",lx[8:4]);
      3:ch=textchar("SOUND VIEW                  ",lx[8:4]);
      4:ch=textchar("CAPTIONS                    ",lx[8:4]);
      5:ch=textchar("REPLAY                      ",lx[8:4]);
      default:;
     endcase
    end
    case(row)0:gain=brightness;1:gain=contrast;2:gain=volume;default:gain=0;endcase
    if(row<3 && x>=288 && x<544 && ly[4:0]>=4 && ly[4:0]<12)
     out_rgb=x-288<gain?24'h70df9a:24'h45556a;
    if(row==1 && x==416 && ly[4:0]<16)out_rgb=24'hffffff; // default contrast
    if(row>=3 && x>=320 && x<544 && ly[4:0]<16)begin
     text_zone=1;lx=x-320;
     case(row)
      3:ch=textchar(wave_mode==0?"OFF                         ":wave_mode==1?"WAVE 42.7MS                 ":"LEVEL 6.4S                  ",lx[8:4]);
      4:ch=textchar(caption_enable?"ON                          ":"OFF                         ",lx[8:4]);
      5:ch=textchar("K2 START                    ",lx[8:4]);
      default:;
     endcase
    end
   end else if(y>=376 && y<408 && x>=96 && x<544)begin
    text_zone=1;lx=x-96;ly=y<392?y-376:y-392;
    ch=textchar(y<392?"K1 FIELD  K2 +  HOLD K2 -   ":"HOLD BOTH FOR GALLERY       ",lx[8:4]);
   end
   if(text_zone)begin
    bitmap=glyph(ch);
    if(lx[3:1]<5 && ly[3:1]<7 && bitmap[34-ly[3:1]*5-lx[3:1]])out_rgb=24'he8f2ff;
   end
  end
 end
endmodule
