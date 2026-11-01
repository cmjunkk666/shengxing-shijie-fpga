// Source descriptor remains held until the original memory-adoption ACK.
// Only whole-frame gain changes; no second image stream or frame buffer.
module media_transition(
 input wire clk,rst,frame_tick,
 input wire source_toggle,source_valid,
 input wire source_gallery,
 input wire [1:0] source_buffer,source_scene,
 input wire [7:0] source_sequence,
 input wire presented_valid,input wire [7:0] presented_sequence,
 output reg commit_toggle,commit_valid,
 output reg commit_gallery,
 output reg [1:0] commit_buffer,commit_scene,
 output reg [7:0] commit_sequence,
 output reg [8:0] gain,
 output wire busy,output reg timeout_fault
);
 localparam IDLE=0,FADE_OUT=1,BLACK=2,WAIT_PRESENT=3,FADE_IN=4;
 reg [2:0] state;
 (* async_reg="true" *) reg [2:0] token_sync,valid_sync;
 reg seen_token,pending_token;
 reg [1:0] pending_buffer,pending_scene;
 reg pending_gallery,pending_same;
 reg [7:0] pending_sequence;
 reg [4:0] wait_frames;
 assign busy=state!=IDLE;
 always @(posedge clk or posedge rst)begin
  if(rst)begin token_sync<=0;valid_sync<=0;end
  else begin token_sync<={token_sync[1:0],source_toggle};valid_sync<={valid_sync[1:0],source_valid};end
 end
 always @(posedge clk or posedge rst)begin
  if(rst)begin
   state<=IDLE;seen_token<=0;pending_token<=0;pending_buffer<=0;pending_scene<=0;pending_sequence<=0;
   commit_toggle<=0;commit_valid<=0;commit_buffer<=0;commit_scene<=0;commit_sequence<=0;commit_gallery<=0;pending_gallery<=0;pending_same<=0;
   gain<=0;wait_frames<=0;timeout_fault<=0;
  end else begin
   if(state==IDLE && valid_sync[2] && token_sync[2]!=seen_token)begin
    seen_token<=token_sync[2];pending_token<=token_sync[2];
    pending_buffer<=source_buffer;pending_scene<=source_scene;pending_sequence<=source_sequence;
    pending_gallery<=source_gallery;
    pending_same<=commit_valid && !source_gallery && !commit_gallery && source_buffer==commit_buffer;
    // Capture first, publish later. Payload settled for three receiver clocks.
    if(!commit_valid || timeout_fault || (!source_gallery && !commit_gallery && source_buffer==commit_buffer)) state<=BLACK;else state<=FADE_OUT;
   end
   if(frame_tick)begin
    case(state)
     FADE_OUT: if(gain<=32)begin gain<=0;state<=BLACK;end else gain<=gain-9'd32;
     BLACK:begin
      commit_buffer<=pending_buffer;commit_scene<=pending_scene;commit_sequence<=pending_sequence;
      commit_gallery<=pending_gallery;
      commit_toggle<=pending_token;commit_valid<=1;wait_frames<=0;
      if(timeout_fault)begin gain<=256;state<=IDLE;end else begin gain<=pending_same?256:0;state<=WAIT_PRESENT;end
     end
     WAIT_PRESENT:begin
      if(presented_valid && presented_sequence==commit_sequence)begin
       if(pending_same)begin gain<=256;state<=IDLE;end
       else begin gain<=32;state<=FADE_IN;end
      end
      else if(wait_frames==15)begin
       // Release the visual fade on failure, retaining the real handshake.
       // Future switches bypass fades until reset; diagnostics remain visible.
       timeout_fault<=1;gain<=32;state<=FADE_IN;
      end else wait_frames<=wait_frames+1'b1;
     end
     FADE_IN:if(gain>=224)begin gain<=256;state<=IDLE;end else gain<=gain+9'd32;
     default:begin end
    endcase
   end
  end
 end
endmodule
