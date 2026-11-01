// Bounded RIFF/WAVE parser. PCM16 LE, 48 kHz, mono or stereo (downmixed).
// Walk chunk headers, including unknown chunks and odd-byte padding. No fixed
// 44-byte assumption. Bytes beyond the RIFF/data bounds cannot become audio.
module wav_pcm_decoder(
 input wire clk,rst,start,input wire [31:0] file_size,
 input wire byte_valid,input wire [7:0] byte_data,output wire byte_ready,
 input wire file_done,input wire [7:0] file_error,
 output wire cancel,output reg format_valid,output reg complete,
 output reg [7:0] error,output wire sample_valid,output wire [15:0] sample_data,
 input wire sample_ready
);
 localparam IDLE=0,RIFF=1,RIFF_CHECK=2,CHUNK=3,CHUNK_CHECK=4,
            FMT=5,FMT_CHECK=6,SKIP=7,PAD=8,DATA=9,TAIL=10,FAILED=11,
            CHUNK_SUM=12,CHUNK_PAD=13,RIFF_SUM=14;
 reg [3:0] state;
 reg [31:0] position,limit,riff_end,riff_size,chunk_id,chunk_size,left;
 reg [31:0] riff_tag,wave_tag,rate,byte_rate;
 reg [15:0] encoding,channels,align,bits;
 reg [4:0] index;
 reg pad_needed,fmt_seen,data_seen;
 reg [1:0] phase;
 reg [7:0] low_byte;
 reg signed [15:0] left_sample;
 wire signed [15:0] incoming=$signed({byte_data,low_byte});
 wire signed [16:0] stereo_sum={left_sample[15],left_sample}+{incoming[15],incoming};
 wire last_byte=(channels==1)?phase==1:phase==3;
 assign sample_valid=state==DATA && byte_valid && last_byte && error==0;
 assign sample_data=channels==1?{byte_data,low_byte}:stereo_sum[16:1];
 assign byte_ready=(state==RIFF || state==CHUNK || state==FMT || state==SKIP || state==PAD ||
                    state==TAIL || state==FAILED) || (state==DATA && (!last_byte || sample_ready));
 assign cancel=state==FAILED;
 wire take=byte_valid && byte_ready;
 reg [32:0] chunk_end,riff_total;
 task fail;input [7:0] code;begin error<=code;format_valid<=0;state<=FAILED;end endtask
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;position<=0;limit<=0;riff_end<=0;riff_size<=0;chunk_id<=0;chunk_size<=0;left<=0;chunk_end<=0;riff_total<=0;
   riff_tag<=0;wave_tag<=0;rate<=0;byte_rate<=0;encoding<=0;channels<=0;align<=0;bits<=0;
   index<=0;pad_needed<=0;fmt_seen<=0;data_seen<=0;phase<=0;low_byte<=0;left_sample<=0;
   format_valid<=0;complete<=0;error<=0;
  end else begin
   if(start)begin
    state<=RIFF;position<=0;limit<=file_size;riff_size<=0;riff_tag<=0;wave_tag<=0;index<=0;
    fmt_seen<=0;data_seen<=0;phase<=0;error<=0;format_valid<=0;complete<=0;
   end else begin
    if(take)begin
     position<=position+1'b1;
     case(state)
      RIFF:begin
       if(index<4)riff_tag[index[1:0]*8 +: 8]<=byte_data;
       else if(index<8)riff_size[index[1:0]*8 +: 8]<=byte_data;
       else wave_tag[index[1:0]*8 +: 8]<=byte_data;
       if(index==11)state<=RIFF_SUM;else index<=index+1'b1;
      end
      CHUNK:begin
       if(index<4)chunk_id[index[1:0]*8 +: 8]<=byte_data;
       else chunk_size[index[1:0]*8 +: 8]<=byte_data;
       if(index==7)state<=CHUNK_SUM;else index<=index+1'b1;
      end
      FMT:begin
       case(index)
        0:encoding[7:0]<=byte_data;1:encoding[15:8]<=byte_data;
        2:channels[7:0]<=byte_data;3:channels[15:8]<=byte_data;
        4:rate[7:0]<=byte_data;5:rate[15:8]<=byte_data;6:rate[23:16]<=byte_data;7:rate[31:24]<=byte_data;
        8:byte_rate[7:0]<=byte_data;9:byte_rate[15:8]<=byte_data;10:byte_rate[23:16]<=byte_data;11:byte_rate[31:24]<=byte_data;
        12:align[7:0]<=byte_data;13:align[15:8]<=byte_data;
        14:bits[7:0]<=byte_data;15:bits[15:8]<=byte_data;
        default:;
       endcase
       left<=left-1'b1;
       if(index==15)state<=FMT_CHECK;else index<=index+1'b1;
      end
      SKIP:begin
       left<=left-1'b1;
       if(left==1)begin state<=pad_needed?PAD:CHUNK;index<=0;end
      end
      PAD:begin state<=CHUNK;index<=0;end
      DATA:begin
       left<=left-1'b1;
       if(!phase[0])low_byte<=byte_data;
       if(phase==1)left_sample<=incoming;
       phase<=last_byte?2'd0:phase+1'b1;
       if(left==1)begin state<=TAIL;data_seen<=1;end
      end
      default:;
     endcase
    end
    case(state)
     // Bounded arithmetic is staged before comparison, keeping all RIFF
     // overflow/boundary checks while meeting the 100 MHz storage clock.
     RIFF_SUM:begin riff_total<={1'b0,riff_size}+33'd8;state<=RIFF_CHECK;end
     CHUNK_SUM:begin chunk_end<={1'b0,position}+{1'b0,chunk_size};state<=CHUNK_PAD;end
     CHUNK_PAD:begin chunk_end<=chunk_end+chunk_size[0];state<=CHUNK_CHECK;end
     RIFF_CHECK:begin
      if(riff_tag!=32'h46464952 || wave_tag!=32'h45564157 || riff_size<36 ||
         riff_total>{1'b0,limit})fail(8'h91);
      else begin riff_end<=riff_total[31:0];index<=0;state<=CHUNK;end
     end
     CHUNK_CHECK:begin
      left<=chunk_size;pad_needed<=chunk_size[0];index<=0;
      if(chunk_end>{1'b0,riff_end})fail(8'h92);
      else if(chunk_id==32'h20746d66)begin
       if(fmt_seen || chunk_size<16)fail(8'h93);else state<=FMT;
      end else if(chunk_id==32'h61746164)begin
       if(!fmt_seen || chunk_size==0 || (channels==1?chunk_size[0]!=0:chunk_size[1:0]!=0))fail(8'h94);
       else begin phase<=0;format_valid<=1;state<=DATA;end
      end else state<=chunk_size==0?CHUNK:SKIP;
     end
     FMT_CHECK:begin
      if(encoding!=1 || (channels!=1 && channels!=2) || bits!=16 || rate!=48000 ||
         align!=(channels==1?16'd2:16'd4) || byte_rate!=(channels==1?32'd96000:32'd192000))fail(8'h95);
      else begin fmt_seen<=1;state<=left!=0?SKIP:(pad_needed?PAD:CHUNK);index<=0;end
     end
     default:;
    endcase
    // A chunk header must fit entirely inside RIFF, even for a malformed file.
    if(state==CHUNK && index==0 && position>riff_size)fail(8'h96);
    if(file_done)begin
     complete<=1;state<=IDLE;
     if(file_error!=0 && error==0)begin error<=file_error;format_valid<=0;end
     else if(error==0 && (!data_seen || phase!=0))begin error<=8'h97;format_valid<=0;end
    end
   end
  end
 end
endmodule
