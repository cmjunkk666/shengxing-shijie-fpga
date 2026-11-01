// Small RGB888 status overlay; no frame/line buffer or image rescaling.
// Status CDC is for display only, sampled for a whole video frame.
module player_osd(
 input wire clk,rst,de,vs,input wire [23:0] rgb,
 input wire display_valid,scan_complete,auto_enabled,
 input wire wav_active,wav_underflow,input wire [7:0] wav_error,
 input wire wave_enable,history_mode,wav_finished,audio_waiting,
 input wire [8:0] brightness,volume,
 input wire [1:0] scene,input wire [3:0] period_seconds,
 input wire [3:0] ready_mask,failed_mask,found_mask,input wire [7:0] error_code,
 output reg [23:0] out_rgb
);
 reg [9:0] x;reg [8:0] y;reg de_old,vs_old;
 (* async_reg="true" *) reg [28:0] status0,status1;
 reg [28:0] status;
 (* async_reg="true" *) reg [10:0] audio0,audio1;reg [10:0] audio_status;
 wire present=status[28],scanned=status[27],auto_on=status[26];
 wire [1:0] pic=status[25:24];wire [3:0] period=status[23:20];
 wire [3:0] ready=status[19:16],failed=status[15:12],found=status[11:8];wire [7:0] error=status[7:0];
 wire [2:0] count={2'b0,ready[0]}+{2'b0,ready[1]}+{2'b0,ready[2]}+{2'b0,ready[3]};
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=0;de_old<=0;vs_old<=0;status0<=0;status1<=0;status<=0;audio0<=0;audio1<=0;audio_status<=0;end
  else begin
   status0<={display_valid,scan_complete,auto_enabled,scene,period_seconds,ready_mask,failed_mask,found_mask,error_code};
   status1<=status0;de_old<=de;vs_old<=vs;audio0<={audio_waiting,wav_active,wav_underflow,wav_error};audio1<=audio0;
   if(vs && !vs_old)begin y<=0;status<=status1;audio_status<=audio1;end
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
  8'd87:glyph=35'b10001100011000110101101011010101010;
  8'd86:glyph=35'b10001100011000110001100010101000100;
  8'd47:glyph=35'b00001000010001000100010001000010000;
  8'd58:glyph=35'b00000001000010000000001000010000000;
  8'd46:glyph=35'b00000000000000000000000000011000110;
  8'd89:glyph=35'b10001100010101000100001000010000100;
  default:glyph=0;
 endcase end endfunction
 function [7:0] hexchar;input [3:0] n;begin hexchar=n<10?8'h30+n:8'h41+n-10;end endfunction
 function [7:0] textchar;input [159:0] s;input [4:0] n;begin textchar=(s>>((19-n)*8));end endfunction
 reg [7:0] ch;reg [34:0] bitmap;reg [4:0] col;reg [2:0] gx,gy;reg [1:0] tile;
 reg ink;reg [23:0] fg;reg [9:0] local_x;reg [8:0] local_y;
 always @* begin
  out_rgb=rgb;ch=32;bitmap=0;col=0;gx=0;gy=0;tile=0;ink=0;fg=24'he8f2ff;local_x=0;local_y=0;
  if(de && x>=8 && x<328 && y>=8 && y<58)begin
   local_x=x-8;col=local_x[8:4];gx=local_x[3:1];
   out_rgb={2'b0,rgb[23:18],2'b0,rgb[15:10],2'b0,rgb[7:2]};
   if(y<24)begin
    local_y=y-8;gy=local_y[3:1];
    if(present)begin
     ch=textchar("PIC 1  MAN   05S    ",col);
     if(col==4)ch="1"+pic;
     if(col>=7 && col<=10)ch=textchar(auto_on?"AUTO                ":"MAN                 ",col-7);
     if(col==13)ch=period==10?"1":"0";if(col==14)ch=period==10?"0":("0"+period);
    end else if(error!=0) ch=textchar("MEDIA ERROR         ",col);
    else if(found!=0 && (found & ~failed)!=0) ch=textchar("LOADING IMAGE       ",col);
    else if(scanned && found==0) ch=textchar("NO BMP FILE         ",col);
    else ch=textchar(scanned?"NO VALID IMAGE      ":"LOADING SD CARD     ",col);
   end else if(y>=26 && y<42)begin
    local_y=y-26;gy=local_y[3:1];ch=textchar("CACHE 0/4           ",col);
    if(col==6)ch="0"+count;
   end else if(y>=44)begin
    local_y=y-44;gy=local_y[3:1];
    if(error!=0)begin ch=textchar("ERROR 00            ",col);fg=24'hff9090;if(col==6)ch=hexchar(error[7:4]);if(col==7)ch=hexchar(error[3:0]);end
    else if(audio_status[7:0]!=0)begin
     ch=textchar("AUDIO ERROR 00      ",col);fg=24'hffb060;
     if(col==12)ch=hexchar(audio_status[7:4]);if(col==13)ch=hexchar(audio_status[3:0]);
    end else if(audio_status[8])begin ch=textchar("AUDIO BUFFER LOW    ",col);fg=24'hffb060;end
    else ch=textchar(audio_status[9]?"AUDIO WAV           ":wav_finished?"AUDIO DONE          ":audio_status[10]?"AUDIO WAIT          ":"AUDIO TONE          ",col);
   end
   bitmap=glyph(ch);ink=gx<5 && gy<7;
   if(ink && bitmap[34-gy*5-gx])out_rgb=fg;
  end
  // B / V bars show configured levels, 0..256, independently of scene fades.
  if(de && x>=344 && x<624 && y>=8 && y<46)begin
   out_rgb={2'b0,rgb[23:18],2'b0,rgb[15:10],2'b0,rgb[7:2]};
   if(x<360)begin
    local_x=x-344;gx=local_x[3:1];local_y=y<27?y-8:y-30;gy=local_y[3:1];
    ch=y<27?"B":"V";bitmap=glyph(ch);
    if((y<24 || y>=30) && gx<5 && gy<7 && bitmap[34-gy*5-gx])out_rgb=24'he8f2ff;
   end else if(x>=368 && ((y>=12 && y<20) || (y>=34 && y<42)))begin
    out_rgb=(x-368<(y<27?brightness:volume))?(y<27?24'h60c8ff:24'h70df9a):24'h35404b;
   end
  end
  // Four scene slots: gray absent, amber discovered, green ready, red failed.
  if(de && x>=8 && x<136 && y>=64 && y<72)begin
   tile=(x-8)>>5;
   if(x[4:0]!=7 && x[4:0]!=6)begin
    out_rgb=failed[tile]?24'hd44848:ready[tile]?24'h38c880:found[tile]?24'hdca53a:24'h45505a;
    if(present && tile==pic && (y==64 || y==71))out_rgb=24'hffffff;
   end
  end
  // Left: Chinese mode label in pcm_wave_overlay. Right: current source.
  if(de && wave_enable && x>=384 && x<576 && y>=286 && y<302)begin
   local_x=x-384;local_y=y-286;col=local_x[8:4];gx=local_x[3:1];gy=local_y[3:1];
   ch=textchar(wav_finished?"AUDIO DONE          ":audio_status[9]?"WAV PLAYING         ":audio_status[10]?"AUDIO WAIT          ":"TONE ACTIVE         ",col);bitmap=glyph(ch);
   out_rgb=24'h101e2c;
   if(gx<5 && gy<7 && bitmap[34-gy*5-gx])out_rgb=24'h60e8b0;
  end
  if(de && x>=8 && x<632 && y>=464 && y<480)begin
   local_x=x<328?x-8:x-328;local_y=y-464;col=local_x[8:4];gx=local_x[3:1];gy=local_y[3:1];
   ch=textchar(x<328?"TAP BOTH MENU       ":"HOLD BOTH GALLERY   ",col);bitmap=glyph(ch);
   out_rgb={2'b0,rgb[23:18],2'b0,rgb[15:10],2'b0,rgb[7:2]};
   if(gx<5 && gy<7 && bitmap[34-gy*5-gx])out_rgb=24'he8f2ff;
  end
 end
endmodule
