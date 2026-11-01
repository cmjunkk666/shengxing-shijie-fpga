// Transaction: A5 opcode length payload CRC8(poly07, init0; excludes A5).
// 10..17 = scene0 title/subtitle, scene1 title/subtitle, ...; 20 = parameters.
// Reply K only after frame commit, E on rejection; host waits for each reply.
// Parameter payload: brightness0..255, volume0..255, flags[2:0], scrollFrames1..16.
// 255 maps to exact gain256. flags: bit0 captions, bit1 scroll, bit2 status.
module scene_caption_overlay(
 input wire clk,rst,de,vs,input wire [23:0] rgb,
 input wire scene_valid,input wire [1:0] scene_id,
 input wire [7:0] scene_theme_map,
 input wire uart_rx,output wire uart_tx,
 input wire local_request,local_decrease,input wire [2:0] local_field,
 output wire de_out,vs_out,output wire [23:0] rgb_out,
 output reg [8:0] brightness,volume,contrast,output wire wave_enable,output reg [1:0] wave_mode,
 output wire status_enable,caption_enable
);
 reg vs_old,de_old;reg [9:0] x;reg [8:0] y;
 wire frame_tick=vs && !vs_old;
 reg [1:0] render_scene;reg render_valid;
 // FAT metadata is stable before the corresponding immutable image is ready.
 // Synchronize it, then select the caption theme at a video frame boundary.
 (* async_reg="true" *) reg [7:0] theme_map0,theme_map1;
 wire [1:0] caption_scene=theme_map1[{scene_id,1'b0} +: 2];
 always @(posedge clk or posedge rst)begin
  if(rst)begin theme_map0<=8'he4;theme_map1<=8'he4;end
  else begin theme_map0<=scene_theme_map;theme_map1<=theme_map0;end
 end
 reg [7:0] active_bank;reg [55:0] lengths;
 reg [2:0] flags;reg [4:0] scroll_frames,scroll_div;
 reg [10:0] scroll_offset;
 assign status_enable=flags[2];
 assign caption_enable=flags[0];
 assign wave_enable=wave_mode!=0;
 wire [2:0] title_field={render_scene,1'b0},sub_field={render_scene,1'b1};
 wire [6:0] title_length=lengths[title_field*7 +: 7];
 wire [6:0] sub_length=lengths[sub_field*7 +: 7];
 // Even short/default subtitles scroll. A ring at least one viewport plus
 // four blank cells wide avoids repeating a short sentence across the row
 // and bounds the renderer to a single subtraction for every length 1..64.
 wire [10:0] scroll_span=sub_length<38?11'd672:({sub_length,4'b0}+11'd64);
 wire rx_valid,rx_error;wire [7:0] rx_data;reg tx_start;reg [7:0] tx_data;wire tx_busy;
 display_uart_rx receiver(.clk(clk),.rst(rst),.rx(uart_rx),.valid(rx_valid),.framing_error(rx_error),.data(rx_data));
 display_uart_tx transmitter(.clk(clk),.rst(rst),.start(tx_start),.data(tx_data),.tx(uart_tx),.busy(tx_busy));
 localparam IDLE=0,COMMAND=1,LENGTH=2,PAYLOAD=3,CHECK=4,COMMIT=5,BOOT=6;
 reg [2:0] state;reg [7:0] command,checksum;reg [6:0] count,packet_length;
 reg [31:0] parameters;reg [20:0] watchdog;reg [9:0] init_address;
 reg reply_pending;reg [7:0] reply;
 (* async_reg="true" *) reg [2:0] local_sync;
 reg local_seen,local_pending,adjust_down;reg [2:0] adjust_field;
 function [8:0] step_gain;input [8:0] gain;input down;
 begin step_gain=down?(gain<=32?9'd0:gain-9'd32):(gain>=224?9'd256:gain+9'd32);end endfunction
 always @(posedge clk or posedge rst)begin
  if(rst)begin local_sync<=0;local_seen<=0;local_pending<=0;adjust_field<=0;adjust_down<=0;end
  else begin
   local_sync<={local_sync[1:0],local_request};
   if(local_pending && frame_tick && state!=BOOT)local_pending<=0;
   if(local_sync[2]!=local_seen)begin
    local_seen<=local_sync[2];local_pending<=1;adjust_field<=local_field;adjust_down<=local_decrease;
   end
  end
 end
 wire text_command=command>=8'h10 && command<=8'h17;
 wire [2:0] write_field=command[2:0];
 wire [9:0] write_address={write_field,~active_bank[write_field],count[5:0]};
 wire timeout=watchdog==21'd1249999; // 50 ms between bytes
 function [7:0] crc8;input [7:0] previous,datum;integer j;reg [7:0] v;
 begin v=previous^datum;for(j=0;j<8;j=j+1)v=v[7]?((v<<1)^8'h07):(v<<1);crc8=v;end endfunction
 function [7:0] default_char;input [8:0] address;begin case(address)
 9'd0:default_char=8'd0;
 9'd1:default_char=8'd239;
 9'd2:default_char=8'd1;
 9'd3:default_char=8'd2;
 9'd64:default_char=8'd3;
 9'd65:default_char=8'd4;
 9'd66:default_char=8'd5;
 9'd67:default_char=8'd171;
 9'd68:default_char=8'd246;
 9'd69:default_char=8'd160;
 9'd70:default_char=8'd223;
 9'd71:default_char=8'd6;
 9'd72:default_char=8'd2;
 9'd73:default_char=8'd7;
 9'd74:default_char=8'd143;
 9'd75:default_char=8'd239;
 9'd76:default_char=8'd8;
 9'd77:default_char=8'd249;
 9'd78:default_char=8'd9;
 9'd79:default_char=8'd173;
 9'd128:default_char=8'd10;
 9'd129:default_char=8'd11;
 9'd130:default_char=8'd12;
 9'd131:default_char=8'd2;
 9'd192:default_char=8'd3;
 9'd193:default_char=8'd12;
 9'd194:default_char=8'd2;
 9'd195:default_char=8'd13;
 9'd196:default_char=8'd14;
 9'd197:default_char=8'd160;
 9'd198:default_char=8'd223;
 9'd199:default_char=8'd6;
 9'd200:default_char=8'd7;
 9'd201:default_char=8'd214;
 9'd202:default_char=8'd143;
 9'd203:default_char=8'd239;
 9'd204:default_char=8'd8;
 9'd205:default_char=8'd239;
 9'd206:default_char=8'd15;
 9'd207:default_char=8'd173;
 9'd256:default_char=8'd16;
 9'd257:default_char=8'd239;
 9'd258:default_char=8'd17;
 9'd259:default_char=8'd18;
 9'd320:default_char=8'd3;
 9'd321:default_char=8'd19;
 9'd322:default_char=8'd20;
 9'd323:default_char=8'd17;
 9'd324:default_char=8'd18;
 9'd325:default_char=8'd160;
 9'd326:default_char=8'd223;
 9'd327:default_char=8'd6;
 9'd328:default_char=8'd214;
 9'd329:default_char=8'd171;
 9'd330:default_char=8'd187;
 9'd331:default_char=8'd20;
 9'd332:default_char=8'd8;
 9'd333:default_char=8'd21;
 9'd334:default_char=8'd22;
 9'd335:default_char=8'd173;
 9'd384:default_char=8'd23;
 9'd385:default_char=8'd24;
 9'd386:default_char=8'd25;
 9'd387:default_char=8'd214;
 9'd448:default_char=8'd3;
 9'd449:default_char=8'd26;
 9'd450:default_char=8'd27;
 9'd451:default_char=8'd25;
 9'd452:default_char=8'd214;
 9'd453:default_char=8'd160;
 9'd454:default_char=8'd223;
 9'd455:default_char=8'd6;
 9'd456:default_char=8'd28;
 9'd457:default_char=8'd29;
 9'd458:default_char=8'd30;
 9'd459:default_char=8'd31;
 9'd460:default_char=8'd8;
 9'd461:default_char=8'd127;
 9'd462:default_char=8'd214;
 9'd463:default_char=8'd173;
 default:default_char=8'd32;
endcase end endfunction
 reg [7:0] text_memory [0:1023]; /* fehdl force_ram=1, ram_style="bram" */
 reg [9:0] text_address;reg [7:0] character;
 reg panel,ink;reg [3:0] glyph_x,glyph_y;reg [10:0] source_x;reg [2:0] field;
 always @(posedge clk)begin
  if(state==BOOT)text_memory[init_address]<=default_char({init_address[9:7],init_address[5:0]});
  else if(state==PAYLOAD && rx_valid && !rx_error && text_command)
   text_memory[write_address]<=rx_data;
  // Disabled/blank caption pixels never consume a character or font word.
  if(ink)character<=text_memory[text_address];
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=BOOT;init_address<=0;active_bank<=0;lengths<=56'h20108042010804;
   command<=0;checksum<=0;count<=0;packet_length<=0;parameters<=0;watchdog<=0;
   reply_pending<=0;reply<=0;tx_start<=0;tx_data<=0;
   // Nature captions occupy the free footer below the question in the BMP.
   // They are observation prompts; no hard-coded WAV timeline is used.
   brightness<=256;volume<=256;contrast<=128;wave_mode<=2;flags<=7;scroll_frames<=3;
  end else begin
   tx_start<=0;
   if(reply_pending && !tx_busy && !tx_start)begin tx_start<=1;tx_data<=reply;reply_pending<=0;end
   if(state==IDLE || state==BOOT || state==COMMIT || rx_valid)watchdog<=0;else watchdog<=watchdog+1'b1;
   if(state==BOOT)begin
    if(init_address==1023)state<=IDLE;else init_address<=init_address+1'b1;
   end else if((rx_error || timeout) && state!=IDLE && state!=COMMIT)begin
    state<=IDLE;reply_pending<=1;reply<=8'h45;
   end else if(state==COMMIT && frame_tick && !local_pending)begin
    if(text_command)begin active_bank[write_field]<=~active_bank[write_field];lengths[write_field*7 +: 7]<=packet_length;end
    else begin
     brightness<=parameters[7:0]==255?9'd256:{1'b0,parameters[7:0]};
     volume<=parameters[15:8]==255?9'd256:{1'b0,parameters[15:8]};
     flags<=parameters[18:16];scroll_frames<=parameters[28:24];
    end
    state<=IDLE;reply_pending<=1;reply<=8'h4b;
   end else if(rx_valid)begin
    case(state)
     IDLE:if(rx_data==8'ha5 && !reply_pending && !tx_busy && !tx_start)begin state<=COMMAND;checksum<=0;end
     COMMAND:begin command<=rx_data;checksum<=crc8(0,rx_data);state<=LENGTH;end
     LENGTH:begin
      count<=0;packet_length<=rx_data[6:0];checksum<=crc8(checksum,rx_data);
      if((text_command && rx_data<= (command[0]?8'd64:8'd32)) || (command==8'h20 && rx_data==4))
       state<=rx_data==0?CHECK:PAYLOAD;
      else begin state<=IDLE;reply_pending<=1;reply<=8'h45;end
     end
     PAYLOAD:begin
      checksum<=crc8(checksum,rx_data);
      if(command==8'h20)parameters[count[1:0]*8 +: 8]<=rx_data;
      if(count+1'b1==packet_length)state<=CHECK;else count<=count+1'b1;
     end
     CHECK:begin
      if(rx_data==checksum && (text_command || (parameters[23:19]==0 && parameters[31:24]>=1 && parameters[31:24]<=16)))state<=COMMIT;
      else begin state<=IDLE;reply_pending<=1;reply<=8'h45;end
     end
     default:begin end
    endcase
   end
   // Apply local adjustments at a frame boundary. UART parsing continues;
   // a pending UART commit waits one frame rather than losing serial bytes.
   if(local_pending && frame_tick && state!=BOOT)begin
    case(adjust_field)
     0:brightness<=step_gain(brightness,adjust_down);
     1:contrast<=step_gain(contrast,adjust_down);
     2:volume<=step_gain(volume,adjust_down);
     3:wave_mode<=adjust_down?(wave_mode==0?2:wave_mode-1'b1):(wave_mode==2?0:wave_mode+1'b1);
     4:flags[0]<=~flags[0];
     default:;
    endcase
   end
  end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin x<=0;y<=0;de_old<=0;vs_old<=0;render_scene<=0;render_valid<=0;scroll_offset<=0;scroll_div<=0;end
  else begin
   de_old<=de;vs_old<=vs;
   if(de)x<=x+1'b1;else x<=0;
   if(frame_tick)begin
    y<=0;render_scene<=caption_scene;render_valid<=scene_valid;
    if(caption_scene!=render_scene || !scene_valid || !render_valid ||
       !flags[0] || !flags[1] || sub_length==0 || state==COMMIT)begin scroll_offset<=0;scroll_div<=0;end
    else if(scroll_div+1'b1>=scroll_frames)begin
     scroll_div<=0;scroll_offset<=scroll_offset+1'b1>=scroll_span?11'd0:scroll_offset+1'b1;
    end else scroll_div<=scroll_div+1'b1;
   end else if(de_old && !de)y<=y+1'b1;
  end
 end
 always @* begin
  panel=0;ink=0;glyph_x=0;glyph_y=0;source_x=0;field=title_field;text_address=0;
  if(de && flags[0] && render_valid)begin
   if(y>=422 && y<442 && x>=8 && x<632 && title_length!=0)begin
    panel=1;
    if(y>=424 && y<440 && x>=16 && x<528)begin
     source_x={1'b0,x}-11'd16;glyph_x=source_x[3:0];glyph_y=y-9'd424;
     ink=source_x[10:4]<title_length;
    end
   end else if(y>=442 && y<462 && x>=8 && x<632 && sub_length!=0)begin
    panel=1;field=sub_field;
    if(y>=444 && y<460 && x>=16 && x<624)begin
     source_x={1'b0,x}-11'd16+(flags[1]?scroll_offset:11'd0);
     if(flags[1] && source_x>=scroll_span)source_x=source_x-scroll_span;
     glyph_x=source_x[3:0];glyph_y=y-9'd444;ink=source_x[10:4]<sub_length;
    end
   end
  end
  text_address={field,active_bank[field],source_x[9:4]};
 end
 reg de1,vs1,de2,vs2,panel1,panel2,ink1,ink2;
 reg [23:0] rgb1,rgb2;reg [3:0] gx1,gx2,gy1;
 wire [15:0] font_pixels;
 display_font_rom font(.clk(clk),.enable(ink1),.address({character,gy1}),.pixels(font_pixels));
 always @(posedge clk or posedge rst)begin
  if(rst)begin de1<=0;vs1<=0;de2<=0;vs2<=0;panel1<=0;panel2<=0;ink1<=0;ink2<=0;rgb1<=0;rgb2<=0;gx1<=0;gx2<=0;gy1<=0;end
  else begin
   de1<=de;vs1<=vs;rgb1<=rgb;panel1<=panel;ink1<=ink;gx1<=glyph_x;gy1<=glyph_y;
   de2<=de1;vs2<=vs1;rgb2<=rgb1;panel2<=panel1;ink2<=ink1;gx2<=gx1;
  end
 end
 assign de_out=de2;assign vs_out=vs2;
 assign rgb_out=(ink2 && font_pixels[15-gx2])?24'hf3f8ff:
                 panel2?{2'b0,rgb2[23:18],2'b0,rgb2[15:10],2'b0,rgb2[7:2]}:rgb2;
endmodule
