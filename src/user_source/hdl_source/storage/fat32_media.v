// Read-only FAT32: first four regular root BMP files, independent of base name.
// Long/Chinese names work through their FAT short entry; display IDs follow directory order.
// One sector owner: the scanner yields between sectors to a requested file.
module fat32_media #(
 parameter integer MAX_ROOT_CLUSTERS=256,
 parameter integer MAX_FILE_BYTES=8388608,
 parameter integer MAX_AUDIO_BYTES=67108864
)(
 input wire clk,rst,start,scan_enable,
 output reg mounted,scan_done,output reg [7:0] fs_error,
 output reg [3:0] found_mask,
 output reg [3:0] audio_mask,
 output reg [7:0] image_audio_map,
 input wire file_start,input wire [2:0] file_id,input wire cancel,
 output wire file_available,output reg file_busy,output reg file_done,
 output reg [7:0] file_error,output wire [31:0] file_size,
 output wire byte_valid,output wire [7:0] byte_data,input wire byte_ready,
 output reg sector_req,output reg [31:0] sector_lba,
 input wire sector_busy,sector_valid,input wire [7:0] sector_data,
 input wire [8:0] sector_index,input wire sector_done,input wire [7:0] sector_error,
 output wire sector_ready
);
 localparam IDLE=0,REQ=1,RX=2,EVAL=3,BPB1=4,BPB2=5,BPB3=6,YIELD=7,
            DIR_ADDR=8,FILE_ADDR=9,FAT_ADDR=10,FILE_FINISH=11,ADDR_SHIFT=12,ADDR_SUM=13,ADDR_FINAL=14,BPB_LIMIT=15,BPB_MOUNT=16;
 localparam BOOT=0,DIR=1,FAT=2,FILE_DATA=3;
 reg [31:0] address_work;reg [7:0] address_sector;
 reg [4:0] state;reg [1:0] kind;
 reg partition_boot,root_need_fat,dir_end,fat_for_file,fat_final,cancel_seen;
 reg [31:0] volume_lba,partition_lba,partition_size,volume_sectors,fat_base,data_base;
 reg [39:0] volume_end,layout_end;
 reg [31:0] cluster_count,root_cluster,file_cluster,fat_target;
 // Volume geometry stays fixed after mount. Precompute its exclusive cluster
 // bound once; avoid a 32-bit add followed by a compare on every FAT hop.
 reg [32:0] cluster_limit;
 // Register independent geometry checks before enabling mount-state updates.
 // The accepted FAT32 range and error codes remain identical.
 reg cluster_count_ok,fat_capacity_ok,root_cluster_ok;
 reg [7:0] root_sector,file_sector;
 reg [15:0] root_hops;
 reg [2:0] candidate_count;
 reg [31:0] remaining;
 reg [31:0] clusters[0:7],sizes[0:7];
 reg [255:0] entry;
 reg entry_pending;
 wire [255:0] full_entry={sector_data,entry[255:8]};
 reg [127:0] part_entry;
 wire [127:0] full_part={sector_data,part_entry[127:8]};
 reg [31:0] fat_value;
 reg [15:0] bps,reserved,root_entries,total16,fat16,flags,version,signature;
 reg [7:0] spc,fats;
 reg [31:0] total32,fat32,bpb_root;
 reg [3:0] spc_shift;
 integer i;
 wire [27:0] next_cluster=fat_value[27:0];
 wire cluster_ok=next_cluster>=2 && {5'b0,next_cluster}<cluster_limit;
 wire eoc=next_cluster>=28'hffffff8;
 wire bmp_extension=(entry[87:64] & 24'hdfdfdf)==24'h504d42;
 // Explicit mapping avoids accidental pairing by FAT directory order.
 // AUDIO1.WAV .. AUDIO4.WAV correspond to displayed PIC 1 .. PIC 4.
 wire wav_entry=(entry[87:64] & 24'hdfdfdf)==24'h564157 &&
   (entry[39:0] & 40'hdfdfdfdfdf)==40'h4f49445541 &&
   entry[63:48]==16'h2020 && entry[47:40]>=8'h31 && entry[47:40]<=8'h34;
 wire [1:0] audio_id=entry[47:40]-8'h31;
 // Named teaching packs pair PICn.BMP with AUDIOn.WAV, regardless of
 // directory discovery order. Other BMP names retain slot-order pairing.
 wire numbered_bmp=(entry[23:0]&24'hdfdfdf)==24'h434950 &&
   entry[31:24]>=8'h31 && entry[31:24]<=8'h34 && entry[63:32]==32'h20202020;
 wire [1:0] numbered_id=entry[31:24]-8'h31;
 wire selected_found=file_id[2]?audio_mask[file_id[1:0]]:found_mask[file_id[1:0]];
 wire regular_entry=entry[7:0]!=8'h00 && entry[7:0]!=8'he5 &&
   (entry[95:88]&8'hd8)==0;
 wire [1:0] entry_id=candidate_count[1:0];
 wire [31:0] entry_cluster={entry[175:160],entry[223:208]};
 wire [31:0] entry_size=entry[255:224];
 assign file_size=sizes[file_id];
 assign file_available=state==YIELD && mounted && !file_busy;
 assign byte_valid=state==RX && kind==FILE_DATA && sector_valid && remaining!=0 && !cancel_seen && !cancel;
 assign byte_data=sector_data;
 assign sector_ready=kind!=FILE_DATA || remaining==0 || cancel_seen || cancel || byte_ready;
 task fs_fail;input [7:0] code;begin fs_error<=code;scan_done<=1;state<=YIELD;end endtask
 task file_fail;input [7:0] code;begin file_error<=code;state<=FILE_FINISH;end endtask
 always @(posedge clk or posedge rst) begin
  if(rst) begin
   address_work<=0;address_sector<=0;state<=IDLE;kind<=BOOT;mounted<=0;scan_done<=0;fs_error<=0;found_mask<=0;audio_mask<=0;image_audio_map<=8'he4;
   file_busy<=0;file_done<=0;file_error<=0;sector_req<=0;sector_lba<=0;
   partition_boot<=0;root_need_fat<=0;volume_lba<=0;partition_lba<=0;partition_size<=0;
   volume_sectors<=0;volume_end<=0;layout_end<=0;fat_base<=0;data_base<=0;
   cluster_count<=0;cluster_limit<=0;root_cluster<=0;file_cluster<=0;fat_target<=0;
   cluster_count_ok<=0;fat_capacity_ok<=0;root_cluster_ok<=0;
   root_sector<=0;file_sector<=0;root_hops<=0;remaining<=0;candidate_count<=0;
   entry<=0;entry_pending<=0;part_entry<=0;dir_end<=0;fat_for_file<=0;fat_final<=0;fat_value<=0;
   cancel_seen<=0;bps<=0;reserved<=0;root_entries<=0;total16<=0;fat16<=0;
   flags<=0;version<=0;signature<=0;spc<=0;fats<=0;total32<=0;fat32<=0;bpb_root<=0;spc_shift<=0;
   for(i=0;i<8;i=i+1) begin clusters[i]<=0;sizes[i]<=0;end
  end else begin
   sector_req<=0;file_done<=0;entry_pending<=0;
   if(file_busy && cancel) cancel_seen<=1;
   // Break the BRAM-byte -> size/attribute checks -> metadata write path.
   // The sector service's completion occurs after this registered entry.
   if(entry_pending && !dir_end)begin
    if(entry[7:0]==0)dir_end<=1;
    else if(candidate_count<4 && bmp_extension && regular_entry &&
      entry_cluster>=2 && entry_cluster<cluster_limit &&
      entry_size>=54 && entry_size<=MAX_FILE_BYTES && !found_mask[entry_id])begin
     found_mask[entry_id]<=1;clusters[entry_id]<=entry_cluster;sizes[entry_id]<=entry_size;
     image_audio_map[{entry_id,1'b0} +: 2]<=numbered_bmp?numbered_id:entry_id;
     candidate_count<=candidate_count+1'b1;
    end else if(wav_entry && regular_entry && entry_cluster>=2 && entry_cluster<cluster_limit &&
      entry_size>=44 && entry_size<=MAX_AUDIO_BYTES && !audio_mask[audio_id])begin
     audio_mask[audio_id]<=1;clusters[{1'b1,audio_id}]<=entry_cluster;sizes[{1'b1,audio_id}]<=entry_size;
    end
   end
   case(state)
    IDLE: if(start) begin
     mounted<=0;scan_done<=0;fs_error<=0;found_mask<=0;audio_mask<=0;image_audio_map<=8'he4;partition_lba<=0;candidate_count<=0;
     partition_size<=0;partition_boot<=0;root_need_fat<=0;volume_lba<=0;sector_lba<=0;kind<=BOOT;state<=REQ;
    end
    REQ: if(!sector_busy) begin
     sector_req<=1;entry<=0;part_entry<=0;fat_value<=0;state<=RX;
    end
    RX: begin
     if(sector_valid && sector_ready) begin
      if(kind==BOOT) begin
       case(sector_index)
        11:bps[7:0]<=sector_data;
        12:bps[15:8]<=sector_data;
        13:spc<=sector_data;
        14:reserved[7:0]<=sector_data;
        15:reserved[15:8]<=sector_data;
        16:fats<=sector_data;
        17:root_entries[7:0]<=sector_data;
        18:root_entries[15:8]<=sector_data;
        19:total16[7:0]<=sector_data;
        20:total16[15:8]<=sector_data;
        22:fat16[7:0]<=sector_data;
        23:fat16[15:8]<=sector_data;
        32:total32[7:0]<=sector_data;
        33:total32[15:8]<=sector_data;
        34:total32[23:16]<=sector_data;
        35:total32[31:24]<=sector_data;
        36:fat32[7:0]<=sector_data;
        37:fat32[15:8]<=sector_data;
        38:fat32[23:16]<=sector_data;
        39:fat32[31:24]<=sector_data;
        40:flags[7:0]<=sector_data;
        41:flags[15:8]<=sector_data;
        42:version[7:0]<=sector_data;
        43:version[15:8]<=sector_data;
        44:bpb_root[7:0]<=sector_data;
        45:bpb_root[15:8]<=sector_data;
        46:bpb_root[23:16]<=sector_data;
        47:bpb_root[31:24]<=sector_data;
        510:signature[7:0]<=sector_data;
        511:signature[15:8]<=sector_data;
        default:;
       endcase
       if(sector_index>=446 && sector_index<510) begin
        part_entry<=full_part;
        if(sector_index[3:0]==4'd13 && partition_lba==0 &&
          (full_part[39:32]==8'h0b || full_part[39:32]==8'h0c) && full_part[95:64]!=0) begin
         partition_lba<=full_part[95:64];partition_size<=full_part[127:96];
        end
       end
      end else if(kind==DIR && !dir_end) begin
       entry<=full_entry;
       if(sector_index[4:0]==31)entry_pending<=1;
      end else if(kind==FAT && sector_index[8:2]==fat_target[6:0]) begin
       case(sector_index[1:0])
        0:fat_value[7:0]<=sector_data;1:fat_value[15:8]<=sector_data;
        2:fat_value[23:16]<=sector_data;3:fat_value[31:24]<=sector_data;
       endcase
      end else if(kind==FILE_DATA && remaining!=0) remaining<=remaining-1'b1;
     end
     if(sector_done) begin
      if(sector_error!=0) begin
       if(file_busy) file_fail(sector_error);else fs_fail(sector_error);
      end else state<=EVAL;
     end
    end
    EVAL: case(kind)
     BOOT: begin
      if(signature!=16'haa55) fs_fail(8'h20);
      else if(bps==512 && fat16==0 && root_entries==0) state<=BPB1;
      else if(!partition_boot && partition_lba!=0 && partition_size!=0) begin
       volume_lba<=partition_lba;sector_lba<=partition_lba;partition_boot<=1;state<=REQ;
      end else fs_fail(8'h21);
     end
     DIR: begin
      if(dir_end || (found_mask==15 && audio_mask==15)) scan_done<=1;
      if(root_sector+1>=spc) begin
       root_sector<=0;root_need_fat<=1;fat_target<=root_cluster;fat_for_file<=0;fat_final<=0;
      end else root_sector<=root_sector+1'b1;
      state<=YIELD;
     end
     FILE_DATA: begin
      if(cancel_seen || cancel) file_fail(8'h40);
      else if(remaining==0 || file_sector+1>=spc) begin
       fat_target<=file_cluster;fat_for_file<=1;fat_final<=remaining==0;state<=FAT_ADDR;
      end else begin file_sector<=file_sector+1'b1;state<=FILE_ADDR;end
     end
     FAT: if(fat_for_file) begin
      if(cancel_seen || cancel) file_fail(8'h40);
      else if(fat_final) begin
       // Exact allocation is required. This also rejects cyclic/overlong chains.
       if(eoc) state<=FILE_FINISH;else file_fail(8'h32);
      end else if(!cluster_ok || eoc) file_fail(8'h31);
      else begin file_cluster<={4'b0,next_cluster};file_sector<=0;state<=FILE_ADDR;end
     end else begin
      if(eoc) begin scan_done<=1;state<=YIELD;end
      else if(!cluster_ok || root_hops>=MAX_ROOT_CLUSTERS) fs_fail(8'h33);
      else begin root_cluster<={4'b0,next_cluster};root_need_fat<=0;root_sector<=0;root_hops<=root_hops+1'b1;state<=DIR_ADDR;end
     end
    endcase
    BPB1: begin
     case(spc)
      1:spc_shift<=0;2:spc_shift<=1;4:spc_shift<=2;8:spc_shift<=3;
      16:spc_shift<=4;32:spc_shift<=5;64:spc_shift<=6;128:spc_shift<=7;
      default:spc_shift<=15;
     endcase
     volume_sectors<=total32;
     volume_end<={1'b0,volume_lba}+{1'b0,total32};
     layout_end<={1'b0,volume_lba}+reserved+({8'b0,fat32} << (fats==2));
     fat_base<=volume_lba+reserved+((flags[7] && flags[3:0]==1)?fat32:0);
     state<=BPB2;
    end
    BPB2: begin
     if(spc_shift==15 || reserved==0 || (fats!=1 && fats!=2) || fat32==0 ||
       flags[6:4]!=0 || flags[15:8]!=0 || (flags[7] && flags[3:0]>=fats) || version!=0 ||
       total16!=0 || total32==0 || (|volume_end[39:32]) || layout_end>=volume_end ||
       (partition_boot && total32>partition_size)) fs_fail(8'h22);
     else begin
      data_base<=layout_end[31:0];cluster_count<=(volume_end-layout_end)>>spc_shift;state<=BPB_LIMIT;
     end
    end
    BPB_LIMIT: begin
     cluster_limit<={1'b0,cluster_count}+33'd2;
     cluster_count_ok<=cluster_count>=65525 && cluster_count<=32'h0fffffee;
     state<=BPB3;
    end
    BPB3: begin
     fat_capacity_ok<=cluster_limit<=({8'b0,fat32}<<7);
     root_cluster_ok<=bpb_root>=2 && bpb_root<cluster_limit;
     state<=BPB_MOUNT;
    end
    BPB_MOUNT: begin
     if(!cluster_count_ok || !fat_capacity_ok || !root_cluster_ok)fs_fail(8'h23);
     else begin mounted<=1;root_cluster<=bpb_root;root_sector<=0;root_hops<=1;dir_end<=0;state<=YIELD;end
    end
    YIELD: if(file_start && mounted && selected_found) begin
     file_busy<=1;file_error<=0;cancel_seen<=0;file_cluster<=clusters[file_id];
     remaining<=sizes[file_id];file_sector<=0;state<=FILE_ADDR;
    end else if(scan_enable && mounted && !scan_done) begin
     if(root_need_fat) begin
      // Previous directory cluster exhausted; file loads may have used fat_target.
      fat_target<=root_cluster;fat_for_file<=0;fat_final<=0;state<=FAT_ADDR;
     end else state<=DIR_ADDR;
    end
    DIR_ADDR: begin address_work<=root_cluster-2;address_sector<=root_sector;kind<=DIR;state<=ADDR_SHIFT;end
    FILE_ADDR: begin address_work<=file_cluster-2;address_sector<=file_sector;kind<=FILE_DATA;state<=ADDR_SHIFT;end
    ADDR_SHIFT: begin address_work<=address_work<<spc_shift;state<=ADDR_SUM;end
    ADDR_SUM: begin address_work<=address_work+data_base;state<=ADDR_FINAL;end
    ADDR_FINAL: begin sector_lba<=address_work+address_sector;state<=REQ;end
    FAT_ADDR: begin sector_lba<=fat_base+(fat_target>>7);kind<=FAT;state<=REQ;end
    FILE_FINISH: begin file_busy<=0;file_done<=1;state<=YIELD;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
