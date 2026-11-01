// Two active-low keys; all logic stays in clk domain.
// KEY1: short=next, long=cycle period. KEY2: short=auto, long=previous.
module key_events #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer LONG_PRESS_MS = 1000
)(
    input wire clk,
    input wire rst,
    input wire key1_n,
    input wire key2_n,
    output reg next_event,
    output reg prev_event,
    output reg toggle_auto_event,
    output reg cycle_period_event,
    output reg gallery_event,
    output reg menu_event,
    output wire interaction_active
);
localparam integer DB_CYCLES = ((CLK_FREQ_HZ / 1000) * DEBOUNCE_MS > 0)
                            ? (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS : 1;
localparam integer HOLD_CYCLES = ((CLK_FREQ_HZ / 1000) * LONG_PRESS_MS > 0)
                              ? (CLK_FREQ_HZ / 1000) * LONG_PRESS_MS : 1;
localparam integer DB_BITS = $clog2(DB_CYCLES + 4);
localparam integer HOLD_BITS = (HOLD_CYCLES < 2) ? 1 : $clog2(HOLD_CYCLES + 1);

reg [1:0] key_meta, key_sync, stable;
reg [DB_BITS-1:0] db_count [0:1];
reg [HOLD_BITS-1:0] hold_count [0:1];
reg [1:0] pressed, long_fired;
reg blocked;
reg chord_armed,chord_fired,chord_pending;
reg [HOLD_BITS-1:0] chord_count;
reg [DB_BITS-1:0] release_count;
integer k;

// Include synchronized raw state so auto play pauses during debounce as well.
assign interaction_active = blocked || (key_sync != 2'b11) || (stable != 2'b11);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        key_meta <= 2'b11;
        key_sync <= 2'b11;
        stable <= 2'b11;
        for (k = 0; k < 2; k = k + 1)
            db_count[k] <= 0;
    end else begin
        key_meta <= {key2_n, key1_n};
        key_sync <= key_meta;
        for (k = 0; k < 2; k = k + 1) begin
            if (key_sync[k] == stable[k])
                db_count[k] <= 0;
            else if (db_count[k] >= DB_CYCLES - 1) begin
                stable[k] <= key_sync[k];
                db_count[k] <= 0;
            end else
                db_count[k] <= db_count[k] + 1'b1;
        end
    end
end

integer j;
always @(posedge clk or posedge rst) begin
    if (rst) begin
        next_event <= 0;
        prev_event <= 0;
        toggle_auto_event <= 0;
        cycle_period_event <= 0;
        gallery_event<=0;menu_event<=0;chord_armed<=0;chord_fired<=0;chord_pending<=0;chord_count<=0;
        pressed <= 0;
        long_fired <= 0;
        blocked <= 1;
        release_count <= 0;
        for (j = 0; j < 2; j = j + 1)
            hold_count[j] <= 0;
    end else begin
        next_event <= 0;
        prev_event <= 0;
        toggle_auto_event <= 0;
        cycle_period_event <= 0;
        gallery_event<=0;
        menu_event<=0;
        if(stable==2'b00 && chord_armed)chord_pending<=1;
        // Both keys held for one second: one gallery gesture, no release click.
        if(stable==2'b00 && chord_armed && !chord_fired)begin
            if(chord_count>=HOLD_CYCLES-1)begin gallery_event<=1;chord_fired<=1;end
            else chord_count<=chord_count+1'b1;
        end else if(stable!=2'b00)chord_count<=0;

        // Power-on/overlap guard: release both keys before accepting another gesture.
        if (blocked || stable == 2'b00) begin
            blocked <= 1;
            pressed <= 0;
            long_fired <= 0;
            hold_count[0] <= 0;
            hold_count[1] <= 0;
            // Require an additional released window after the synchronizer fills.
            if (key_sync == 2'b11 && stable == 2'b11) begin
                if (release_count >= DB_CYCLES + 2) begin
                    blocked <= 0;
                    chord_armed<=1;chord_fired<=0;
                    if(chord_pending && !chord_fired)menu_event<=1;
                    chord_pending<=0;
                    release_count <= 0;
                end else
                    release_count <= release_count + 1'b1;
            end else
                release_count <= 0;
        end else begin
            release_count <= 0;
            for (j = 0; j < 2; j = j + 1) begin
                if (!stable[j]) begin
                    pressed[j] <= 1;
                    if (!long_fired[j]) begin
                        if (hold_count[j] >= HOLD_CYCLES - 1) begin
                            long_fired[j] <= 1;
                            if (j == 0) cycle_period_event <= 1;
                            else prev_event <= 1;
                        end else
                            hold_count[j] <= hold_count[j] + 1'b1;
                    end
                end else begin
                    if (pressed[j] && !long_fired[j]) begin
                        if (j == 0) next_event <= 1;
                        else toggle_auto_event <= 1;
                    end
                    pressed[j] <= 0;
                    long_fired[j] <= 0;
                    hold_count[j] <= 0;
                end
            end
        end
    end
end
endmodule
