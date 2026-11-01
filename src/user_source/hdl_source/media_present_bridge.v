// Bundled-data CDC: source holds descriptor until adoption_ack equals request.
// Pixel selector stays fixed for the entire mem request/ack/adoption handshake.
// No source buffer can be recycled before the memory reader has adopted it.
module media_present_bridge(
    input wire clk, rst,
    input wire commit_toggle, source_valid,
    input wire commit_gallery,
    input wire [1:0] commit_buffer, commit_scene,
    input wire [7:0] commit_sequence,
    output reg adoption_ack,
    input wire frame_request,
    output reg frame_request_ack,
    output reg memory_request,
    input wire memory_ack, memory_adopt_toggle,
    input wire [1:0] memory_adopt_buffer,
    input wire memory_adopt_gallery,
    output reg [1:0] selected_buffer,
    output reg selected_gallery,output reg scene_gallery,
    input wire pixel_read, fifo_empty,
    input wire axis_sof, axis_valid, axis_ready, video_locked,
    output wire pixels_valid,
    output reg scene_event, scene_valid,
    output reg [1:0] scene_id,
    output reg [7:0] scene_sequence,
    output reg [15:0] late_count, underflow_count, protocol_count
);
(* async_reg="true" *) reg [2:0] commit_sync, ack_sync, adopt_sync, valid_sync;
reg [1:0] handshake;
localparam IDLE=0, WAIT_ACK=1, WAIT_ADOPT=2;
reg request_seen, adopt_seen, selected_token, selected_valid;
reg [1:0] selected_scene;
reg [7:0] selected_sequence;
reg frame_ready, frame_bad, frame_started;
wire new_adoption=adopt_sync[2]!=adopt_seen;
assign pixels_valid=frame_ready && selected_valid && valid_sync[2] && !frame_bad;
always @(posedge clk or posedge rst) begin
    if(rst) begin commit_sync<=0; ack_sync<=0; adopt_sync<=0; valid_sync<=0; end
    else begin
        commit_sync<={commit_sync[1:0],commit_toggle};
        ack_sync<={ack_sync[1:0],memory_ack};
        adopt_sync<={adopt_sync[1:0],memory_adopt_toggle};
        valid_sync<={valid_sync[1:0],source_valid};
    end
end
always @(posedge clk or posedge rst) begin
    if(rst) begin
        adoption_ack<=0; frame_request_ack<=0; memory_request<=0;
        selected_buffer<=0; selected_scene<=0; selected_sequence<=0; selected_token<=0;selected_gallery<=0;scene_gallery<=0;
        selected_valid<=0; request_seen<=0; adopt_seen<=0; handshake<=IDLE;
        frame_ready<=0; frame_bad<=0; frame_started<=0;
        scene_event<=0; scene_valid<=0; scene_id<=0; scene_sequence<=0;
        late_count<=0; underflow_count<=0; protocol_count<=0;
    end else begin
        frame_request_ack<=0; scene_event<=0;
        if(!frame_request) request_seen<=0;
        if(!video_locked || !valid_sync[2]) scene_valid<=0;
        if(frame_request && !request_seen) begin
            request_seen<=1; frame_request_ack<=1;
            frame_ready<=0; frame_started<=0;
            if(handshake==IDLE && !ack_sync[2]) begin
                frame_bad<=0;
                if(commit_sync[2]!=adoption_ack) begin
                    // Data has been stable throughout the three-stage request synchronizer.
                    selected_buffer<=commit_buffer; selected_scene<=commit_scene;
                    selected_gallery<=commit_gallery;
                    selected_sequence<=commit_sequence; selected_token<=commit_sync[2];
                    selected_valid<=valid_sync[2];
                end else if(!valid_sync[2]) selected_valid<=0;
                memory_request<=1; handshake<=WAIT_ACK;
            end else begin
                frame_bad<=1; scene_valid<=0;
                if(protocol_count!=16'hffff) protocol_count<=protocol_count+1'b1;
            end
        end
        if(handshake==WAIT_ACK && ack_sync[2]) begin
            memory_request<=0; handshake<=WAIT_ADOPT;
        end
        if(new_adoption) begin
            adopt_seen<=adopt_sync[2];
            if(handshake==WAIT_ADOPT && memory_adopt_buffer==selected_buffer && memory_adopt_gallery==selected_gallery) begin
                handshake<=IDLE; frame_ready<=1;
                // Acknowledge ownership even if this frame was too late for display.
                // The old buffer is now safe; do NOT invent a presentation event.
                adoption_ack<=selected_token;
            end else begin
                frame_bad<=1; scene_valid<=0;
                if(protocol_count!=16'hffff) protocol_count<=protocol_count+1'b1;
            end
        end
        // Observe the real FIFO read boundary, before the video output delay.
        if(pixel_read && selected_valid && valid_sync[2] && !frame_bad) begin
            if(!frame_ready) begin
                frame_bad<=1; scene_valid<=0;
                if(late_count!=16'hffff) late_count<=late_count+1'b1;
            end else if(fifo_empty) begin
                frame_bad<=1; scene_valid<=0;
                if(underflow_count!=16'hffff) underflow_count<=underflow_count+1'b1;
            end
        end
        if(axis_valid && video_locked && !axis_ready && !frame_bad) begin
            frame_bad<=1; scene_valid<=0;
            if(protocol_count!=16'hffff) protocol_count<=protocol_count+1'b1;
        end
        if(axis_sof && axis_valid) begin
            frame_started<=1;
            if(pixels_valid && !frame_started && axis_ready && video_locked &&
               !(pixel_read && fifo_empty)) begin
                scene_valid<=1;
                scene_gallery<=selected_gallery;
                if(!scene_valid || scene_sequence!=selected_sequence) begin
                    scene_event<=1; scene_id<=selected_scene;
                    scene_sequence<=selected_sequence;
                end
            end else begin
                scene_valid<=0;
                if(selected_valid && (!frame_ready || frame_started) && !frame_bad) begin
                    frame_bad<=1;
                    if(late_count!=16'hffff) late_count<=late_count+1'b1;
                end
            end
        end
    end
end
endmodule
