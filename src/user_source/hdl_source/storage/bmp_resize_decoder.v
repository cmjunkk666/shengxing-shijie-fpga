// RGB24, uncompressed bottom-up BMP, 1..1920 by 1..1080. A single source
// scanline is enough for nearest-neighbour resizing to a letterboxed 640x480
// cache. SD byte delivery and cache output both have explicit backpressure.
// Output remains bottom-up; the existing SDRAM writer supplies the final flip.
module bmp_resize_decoder(
 input wire clk,rst,start,input wire [31:0] file_size,
 input wire byte_valid,input wire [7:0] byte_data,output wire byte_ready,
 input wire file_done,input wire pixel_ready,
 output reg pixel_valid,output reg [23:0] pixel_data,
 output reg done,output reg [7:0] error,output wire cancel,
 output reg [18:0] pixel_count
);
 localparam IDLE=0,HEADER=1,CHECK_HEADER=2,SIZE1=3,SIZE2=4,DIVIDE=5,LAYOUT=6,
            BLACK=7,OFFSET=8,BODY=9,PADDING=10,ROW_READY=11,FETCH=12,EMIT=13,
            X_STEP=14,Y_STEP=15,Y_READY=16,ROW_NEXT=17,TAIL=18,FAILED=19,SIZE_CHECK=20;
 reg [4:0] state;
 reg active,file_ended,wide_fit,image_done,trailing_black;
 reg [31:0] position,expected_size,offset,bmp_size,dib,width,height,compression,image_size;
 reg [15:0] signature,planes,bpp;
 reg [31:0] stride,source_bytes;
 reg [32:0] pixel_end;
 reg [20:0] div_num,div_result;
 reg [12:0] div_rem;
 reg [11:0] divisor;
 reg [4:0] div_steps;
 wire [12:0] trial={div_rem[11:0],div_num[20]};
 wire [20:0] fit_width=width[10:0]*21'd480,fit_height=height[10:0]*21'd640;
 wire [9:0] fitted_width=wide_fit?10'd640:(div_result==0?10'd1:div_result[9:0]);
 wire [8:0] fitted_height=wide_fit?(div_result==0?9'd1:div_result[8:0]):9'd480;
 reg [9:0] scaled_width,pad_x,end_x,out_x;
 reg [8:0] scaled_height,black_rows,image_rows;
 reg [10:0] source_y,wanted_y,in_x,sample_x;
 reg [10:0] last_source_x,last_source_y;
 reg [8:0] last_image_row;
 reg [12:0] x_error,y_error;
 reg [1:0] phase,pad_left;
 reg [7:0] blue,green;
 reg [23:0] line_memory[0:2047];
 reg [23:0] line_pixel;
 wire picture_column=out_x>=pad_x && out_x<end_x;
 wire selected_row=source_y==wanted_y && !image_done;
 wire take=byte_valid && byte_ready;
 // After SIZE2, offset counts the bytes still to skip. Keep a 32-bit
 // magnitude comparison out of byte_ready and every byte-accept state path.
 assign byte_ready=active && (state==HEADER || (state==OFFSET && offset!=0) ||
                   state==BODY || state==PADDING || state==TAIL || state==FAILED);
 assign cancel=active && error!=0;
 always @(posedge clk)begin
  if(state==BODY && take && phase==2 && selected_row)line_memory[in_x]<={byte_data,green,blue};
  if(state==FETCH && picture_column)line_pixel<=line_memory[sample_x];
 end
 task fail;input [7:0] code;begin error<=code;state<=FAILED;end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;active<=0;file_ended<=0;wide_fit<=0;image_done<=0;trailing_black<=0;
   position<=0;expected_size<=0;offset<=0;bmp_size<=0;dib<=0;width<=0;height<=0;compression<=0;image_size<=0;
   signature<=0;planes<=0;bpp<=0;stride<=0;source_bytes<=0;pixel_end<=0;
   div_num<=0;div_result<=0;div_rem<=0;divisor<=0;div_steps<=0;
   scaled_width<=0;pad_x<=0;end_x<=0;out_x<=0;scaled_height<=0;black_rows<=0;image_rows<=0;
   source_y<=0;wanted_y<=0;in_x<=0;sample_x<=0;last_source_x<=0;last_source_y<=0;last_image_row<=0;
   x_error<=0;y_error<=0;phase<=0;pad_left<=0;blue<=0;green<=0;
   pixel_valid<=0;pixel_data<=0;pixel_count<=0;done<=0;error<=0;
  end else begin
   pixel_valid<=0;done<=0;
   if(start)begin
    state<=HEADER;active<=1;file_ended<=0;position<=0;expected_size<=file_size;
    error<=0;pixel_count<=0;image_rows<=0;image_done<=0;trailing_black<=0;
    source_y<=0;wanted_y<=0;in_x<=0;sample_x<=0;out_x<=0;phase<=0;x_error<=0;y_error<=0;
   end else if(active)begin
    if(file_done)file_ended<=1;
    if(take)position<=position+1'b1;
    case(state)
     HEADER:if(take)begin
      case(position)
       0:signature[7:0]<=byte_data;1:signature[15:8]<=byte_data;
       2:bmp_size[7:0]<=byte_data;3:bmp_size[15:8]<=byte_data;4:bmp_size[23:16]<=byte_data;5:bmp_size[31:24]<=byte_data;
       10:offset[7:0]<=byte_data;11:offset[15:8]<=byte_data;12:offset[23:16]<=byte_data;13:offset[31:24]<=byte_data;
       14:dib[7:0]<=byte_data;15:dib[15:8]<=byte_data;16:dib[23:16]<=byte_data;17:dib[31:24]<=byte_data;
       18:width[7:0]<=byte_data;19:width[15:8]<=byte_data;20:width[23:16]<=byte_data;21:width[31:24]<=byte_data;
       22:height[7:0]<=byte_data;23:height[15:8]<=byte_data;24:height[23:16]<=byte_data;25:height[31:24]<=byte_data;
       26:planes[7:0]<=byte_data;27:planes[15:8]<=byte_data;28:bpp[7:0]<=byte_data;29:bpp[15:8]<=byte_data;
       30:compression[7:0]<=byte_data;31:compression[15:8]<=byte_data;32:compression[23:16]<=byte_data;33:compression[31:24]<=byte_data;
       34:image_size[7:0]<=byte_data;35:image_size[15:8]<=byte_data;36:image_size[23:16]<=byte_data;37:image_size[31:24]<=byte_data;
       default:;
      endcase
      if(position==53)state<=CHECK_HEADER;
     end
     CHECK_HEADER:begin
      if(signature!=16'h4d42 || (dib!=40 && dib!=108 && dib!=124) || planes!=1 || bpp!=24 ||
         compression!=0 || width==0 || width>1920 || height==0 || height>1080 ||
         {1'b0,dib}+33'd14>{1'b0,offset})fail(8'h50);
      else begin
       stride<=((width<<1)+width+3)&32'hfffffffc;
       last_source_x<=width[10:0]-1'b1;last_source_y<=height[10:0]-1'b1;
       wide_fit<=fit_width>=fit_height;
       div_num<=fit_width>=fit_height?fit_height:fit_width;
       divisor<=fit_width>=fit_height?width[11:0]:height[11:0];
       div_rem<=0;div_result<=0;div_steps<=21;state<=SIZE1;
      end
     end
     SIZE1:begin source_bytes<=stride[12:0]*height[10:0];state<=SIZE2;end
     SIZE2:begin
      pixel_end<={1'b0,offset}+{1'b0,source_bytes};
      // HEADER always consumes exactly 54 bytes; CHECK_HEADER guarantees
      // absolute offset >= 14 + supported DIB size >= 54 before reaching here.
      offset<=offset-32'd54;
      state<=SIZE_CHECK;
     end
     SIZE_CHECK:begin
      if(pixel_end>{1'b0,expected_size} || bmp_size>expected_size ||
         {1'b0,bmp_size}<pixel_end || (image_size!=0 && image_size!=source_bytes))fail(8'h50);
      else state<=DIVIDE;
     end
     DIVIDE:begin
      div_num<={div_num[19:0],1'b0};div_steps<=div_steps-1'b1;
      if(trial>={1'b0,divisor})begin div_rem<=trial-{1'b0,divisor};div_result<={div_result[19:0],1'b1};end
      else begin div_rem<=trial;div_result<={div_result[19:0],1'b0};end
      if(div_steps==1)state<=LAYOUT;
     end
     LAYOUT:begin
      scaled_width<=fitted_width;scaled_height<=fitted_height;
      last_image_row<=fitted_height-1'b1;
      pad_x<=(10'd640-fitted_width)>>1;end_x<=((10'd640-fitted_width)>>1)+fitted_width;
      black_rows<=(9'd480-fitted_height)>>1;out_x<=0;
      state<=fitted_height>=479?OFFSET:BLACK;
     end
     BLACK:if(pixel_ready)begin
      pixel_data<=0;pixel_valid<=1;pixel_count<=pixel_count+1'b1;
      if(out_x==639)begin
       out_x<=0;
       if(black_rows==1)begin black_rows<=0;state<=trailing_black?ROW_NEXT:OFFSET;end
       else black_rows<=black_rows-1'b1;
      end else out_x<=out_x+1'b1;
     end
     OFFSET:if(offset==0)state<=BODY;
            else if(take)offset<=offset-1'b1;
     BODY:if(take)begin
      case(phase)
       0:begin blue<=byte_data;phase<=1;end
       1:begin green<=byte_data;phase<=2;end
       2:begin
        phase<=0;
        if(in_x==last_source_x)begin
         in_x<=0;pad_left<=width[1:0];
         state<=width[1:0]==0?ROW_READY:PADDING;
        end else in_x<=in_x+1'b1;
       end
      endcase
     end
     PADDING:if(take)begin
      if(pad_left==1)begin pad_left<=0;state<=ROW_READY;end else pad_left<=pad_left-1'b1;
     end
     ROW_READY:begin
      if(selected_row)begin out_x<=0;sample_x<=0;x_error<=0;state<=FETCH;end
      else state<=ROW_NEXT;
     end
     FETCH:state<=EMIT;
     EMIT:if(pixel_ready)begin
      pixel_data<=picture_column?line_pixel:24'd0;pixel_valid<=1;pixel_count<=pixel_count+1'b1;
      if(out_x==639)begin
       out_x<=0;image_rows<=image_rows+1'b1;
       if(image_rows==last_image_row)begin
        image_done<=1;black_rows<=9'd480-scaled_height-((9'd480-scaled_height)>>1);trailing_black<=1;
        state<=scaled_height==480?ROW_NEXT:BLACK;
       end else begin y_error<=y_error+height[10:0];state<=Y_STEP;end
      end else begin
       out_x<=out_x+1'b1;
       if(picture_column)begin x_error<=x_error+width[10:0];state<=X_STEP;end
       else state<=FETCH;
      end
     end
     X_STEP:if(x_error>={3'd0,scaled_width})begin
      x_error<=x_error-{3'd0,scaled_width};sample_x<=sample_x+1'b1;
     end else state<=FETCH;
     Y_STEP:if(y_error>={4'd0,scaled_height})begin
      y_error<=y_error-{4'd0,scaled_height};wanted_y<=wanted_y+1'b1;
     end else state<=Y_READY;
     Y_READY:if(wanted_y==source_y)begin out_x<=0;sample_x<=0;x_error<=0;state<=FETCH;end else state<=ROW_NEXT;
     ROW_NEXT:if(source_y==last_source_y)state<=TAIL;
      else begin source_y<=source_y+1'b1;state<=BODY;end
     TAIL:if(file_ended || file_done)begin
      if(pixel_count!=307200 || position<pixel_end)error<=8'h51;
      active<=0;done<=1;state<=IDLE;
     end
     FAILED:if(file_ended || file_done)begin active<=0;done<=1;state<=IDLE;end
     default:;
    endcase
    if(file_done && state!=FAILED && state!=TAIL &&
       (state<=SIZE2 || {1'b0,position}<pixel_end))fail(8'h51);
   end
  end
 end
endmodule
