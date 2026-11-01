// Segment encoding follows the existing six-digit board constraints.
// Slot 0..5: picture, count, A/H, period tens, period units, source state.
// Picture dot = image loading; source state dot = scan finished with no pictures.
module player_status_display(
    input wire display_valid,
    input wire scan_complete,
    input wire loading,
    input wire [2:0] picture_number,
    input wire [2:0] picture_count,
    input wire auto_enabled,
    input wire [3:0] period_seconds,
    input wire [3:0] source_state,
    output wire [7:0] digit0,
    output wire [7:0] digit1,
    output wire [7:0] digit2,
    output wire [7:0] digit3,
    output wire [7:0] digit4,
    output wire [7:0] digit5
);
function [6:0] hex_segments;
    input [3:0] value;
    begin
        case (value)
            0: hex_segments = 7'b1000000;
            1: hex_segments = 7'b1111001;
            2: hex_segments = 7'b0100100;
            3: hex_segments = 7'b0110000;
            4: hex_segments = 7'b0011001;
            5: hex_segments = 7'b0010010;
            6: hex_segments = 7'b0000010;
            7: hex_segments = 7'b1111000;
            8: hex_segments = 7'b0000000;
            9: hex_segments = 7'b0010000;
            10: hex_segments = 7'b0001000;
            11: hex_segments = 7'b0000011;
            12: hex_segments = 7'b1000110;
            13: hex_segments = 7'b0100001;
            14: hex_segments = 7'b0000110;
            default: hex_segments = 7'b0001110;
        endcase
    end
endfunction
assign digit0 = {~loading, display_valid ? hex_segments({1'b0, picture_number}) : 7'b0111111};
assign digit1 = {1'b1, hex_segments({1'b0, picture_count})};
assign digit2 = {1'b1, auto_enabled ? 7'b0001000 : 7'b0001001}; // A / H(hand)
assign digit3 = {1'b1, hex_segments(period_seconds == 10 ? 4'd1 : 4'd0)};
assign digit4 = {1'b1, hex_segments(period_seconds == 10 ? 4'd0 : period_seconds)};
assign digit5 = {~(scan_complete && picture_count == 0), hex_segments(source_state)};
endmodule
