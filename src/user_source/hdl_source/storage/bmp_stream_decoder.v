// Strict 640x480 RGB888 BMP stream decoder; bottom-up rows are remapped by writer.
module bmp_stream_decoder(
 input wire clk,rst,start,input wire [31:0] file_size,
 input wire byte_valid,input wire [7:0] byte_data,input wire file_done,
 output reg pixel_valid,output reg [23:0] pixel_data,
 output reg done,output reg [7:0] error,output wire cancel,
 output reg [18:0] pixel_count
);
 reg active,header_ok;
 reg [31:0] offset,bmp_size,dib,width,height,compression,image_size;
 reg [15:0] signature,planes,bpp;
 reg [31:0] position,expected_size;
 reg [1:0] phase;reg [7:0] blue,green;
 wire [32:0] pixel_end={1'b0,offset}+33'd921600;
 wire [32:0] header_end={1'b0,dib}+33'd14;
 assign cancel=active && error!=0;
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   active<=0;header_ok<=0;offset<=0;bmp_size<=0;dib<=0;width<=0;height<=0;
   compression<=0;image_size<=0;signature<=0;planes<=0;bpp<=0;position<=0;
   phase<=0;blue<=0;green<=0;pixel_valid<=0;pixel_data<=0;done<=0;error<=0;pixel_count<=0;expected_size<=0;
  end else begin
   pixel_valid<=0;done<=0;
   if(start) begin
    active<=1;header_ok<=0;position<=0;error<=0;pixel_count<=0;phase<=0;expected_size<=file_size;
   end else if(active) begin
    if(byte_valid && error==0) begin
     position<=position+1'b1;
     if(position<54) begin
      case(position)
       0:signature[7:0]<=byte_data;
       1:signature[15:8]<=byte_data;
       2:bmp_size[7:0]<=byte_data;
       3:bmp_size[15:8]<=byte_data;
       4:bmp_size[23:16]<=byte_data;
       5:bmp_size[31:24]<=byte_data;
       10:offset[7:0]<=byte_data;
       11:offset[15:8]<=byte_data;
       12:offset[23:16]<=byte_data;
       13:offset[31:24]<=byte_data;
       14:dib[7:0]<=byte_data;
       15:dib[15:8]<=byte_data;
       16:dib[23:16]<=byte_data;
       17:dib[31:24]<=byte_data;
       18:width[7:0]<=byte_data;
       19:width[15:8]<=byte_data;
       20:width[23:16]<=byte_data;
       21:width[31:24]<=byte_data;
       22:height[7:0]<=byte_data;
       23:height[15:8]<=byte_data;
       24:height[23:16]<=byte_data;
       25:height[31:24]<=byte_data;
       26:planes[7:0]<=byte_data;
       27:planes[15:8]<=byte_data;
       28:bpp[7:0]<=byte_data;
       29:bpp[15:8]<=byte_data;
       30:compression[7:0]<=byte_data;
       31:compression[15:8]<=byte_data;
       32:compression[23:16]<=byte_data;
       33:compression[31:24]<=byte_data;
       34:image_size[7:0]<=byte_data;
       35:image_size[15:8]<=byte_data;
       36:image_size[23:16]<=byte_data;
       37:image_size[31:24]<=byte_data;
       default:;
      endcase
      if(position==53) begin
       if(signature!=16'h4d42 || (dib!=40 && dib!=108 && dib!=124) || width!=640 || height!=480 || planes!=1 || bpp!=24 ||
          compression!=0 || header_end>{1'b0,offset} || pixel_end>{1'b0,expected_size} ||
          bmp_size< pixel_end || bmp_size>expected_size || (image_size!=0 && image_size!=921600)) error<=8'h50;
       else header_ok<=1;
      end
     end else if(header_ok && position>=offset && {1'b0,position}<pixel_end) begin
      case(phase)
       0:begin blue<=byte_data;phase<=1;end
       1:begin green<=byte_data;phase<=2;end
       2:begin pixel_data<={byte_data,green,blue};pixel_valid<=1;pixel_count<=pixel_count+1'b1;phase<=0;end
      endcase
     end
    end
    if(file_done) begin
     active<=0;done<=1;
     if(error==0 && (!header_ok || pixel_count!=307200 || phase!=0)) error<=8'h51;
    end
   end
  end
 end
endmodule
