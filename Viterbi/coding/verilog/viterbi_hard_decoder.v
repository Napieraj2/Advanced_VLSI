`timescale 1ns/1ps

module viterbi_hard_decoder #(
    parameter TB_DEPTH = 12,
    parameter METRIC_W = 16,
    // PIPELINE = 0 -> baseline (bit-exact original behavior)
    // PIPELINE = 1 -> insert one input-side register stage (+1 cycle latency)
    parameter PIPELINE  = 1,
    // NORMALIZE = 0 -> baseline (no path-metric normalization)
    // NORMALIZE = 1 -> after each ACS step, subtract the minimum reachable
    //                  path metric from every reachable state.  Argmax is
    //                  preserved (a constant offset cancels in every
    //                  pairwise compare), so decoded output is unchanged,
    //                  but the registered path metrics no longer drift
    //                  with symbol count.  Per-symbol BM is bounded to
    //                  {-2,0,+2}, but accumulated path metrics still grow
    //                  unboundedly and wrap the signed 16-bit range after
    //                  ~16k symbols on continuous streams.
    parameter NORMALIZE = 1
) (
    input                      clk,
    input                      rst_n,
    input                      in_valid,
    input                      rx0,
    input                      rx1,
    output reg                 decoded_valid,
    output reg                 decoded_bit
);

    localparam NUM_STATES = 4;
    localparam STATE_W    = 2;
    // METRIC_MIN = -(2^(METRIC_W-1) - 1). Built as the explicit bit pattern
    // 1_0..0_1 so Quartus does not flag a constant overflow on the arithmetic.
    localparam signed [METRIC_W-1:0] METRIC_MIN = {1'b1, {(METRIC_W-2){1'b0}}, 1'b1};

    reg signed [METRIC_W-1:0] path_metric      [0:NUM_STATES-1];
    reg signed [METRIC_W-1:0] next_path_metric [0:NUM_STATES-1];

    reg [STATE_W-1:0] survivor_prev      [0:TB_DEPTH-1][0:NUM_STATES-1];
    reg [STATE_W-1:0] next_survivor_prev [0:TB_DEPTH-1][0:NUM_STATES-1];
    reg               survivor_bit       [0:TB_DEPTH-1][0:NUM_STATES-1];
    reg               next_survivor_bit  [0:TB_DEPTH-1][0:NUM_STATES-1];

    reg [TB_DEPTH:0] sym_count;
    reg [TB_DEPTH:0] next_sym_count;

    reg next_decoded_valid;
    reg next_decoded_bit;

    reg [STATE_W-1:0] best_prev [0:NUM_STATES-1];
    reg               best_bit  [0:NUM_STATES-1];
    reg [STATE_W-1:0] best_state;
    reg signed [METRIC_W-1:0] best_metric;
    reg [STATE_W-1:0] prev_state;
    reg [STATE_W-1:0] dst_state;
    reg               in_bit;
    reg [1:0]         expected_bits;
    reg signed [METRIC_W-1:0] cand_metric;
    reg [STATE_W-1:0] tb_state;
    reg [TB_DEPTH-1:0] tb_bits;
    reg signed [METRIC_W-1:0] min_metric;
    reg signed [METRIC_W-1:0] min_offset_next;
    reg signed [METRIC_W-1:0] min_offset_q;

    integer s;
    integer d;
    integer b;

    // ====================================================================
    // === PIPELINE additions: optional input register stage (PIPELINE=1) =
    // Registers the hard-decision inputs and in_valid one cycle ahead of
    // the BMU/ACS combinational logic.  Adds +1 cycle of decode latency.
    // When PIPELINE=0 these regs go unused and Quartus prunes them, so
    // baseline synthesis is unchanged.
    // ====================================================================
    reg rx0_q;
    reg rx1_q;
    reg in_valid_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx0_q      <= 1'b0;
            rx1_q      <= 1'b0;
            in_valid_q <= 1'b0;
        end else begin
            rx0_q      <= rx0;
            rx1_q      <= rx1;
            in_valid_q <= in_valid;
        end
    end

    wire rx0_eff      = (PIPELINE != 0) ? rx0_q      : rx0;
    wire rx1_eff      = (PIPELINE != 0) ? rx1_q      : rx1;
    wire in_valid_eff = (PIPELINE != 0) ? in_valid_q : in_valid;
    // ====================================================================
    // === end PIPELINE additions =========================================
    // ====================================================================

    function [1:0] enc_out;
        input [1:0] prev_state;
        input       in_bit;
        reg c0;
        reg c1;
        begin
            c0 = in_bit ^ prev_state[1] ^ prev_state[0];
            c1 = in_bit ^ prev_state[0];
            enc_out = {c0, c1};
        end
    endfunction

    function signed [METRIC_W-1:0] branch_metric;
        input hard_rx0;
        input hard_rx1;
        input [1:0] expected;
        reg signed [METRIC_W-1:0] m;
        reg signed [METRIC_W-1:0] one;
        begin
            // Sized +/-1 so Quartus does not truncate 32-bit ternary results.
            one = {{(METRIC_W-1){1'b0}}, 1'b1};
            m = 0;
            m = m + ((expected[1] == hard_rx0) ? one : -one);
            m = m + ((expected[0] == hard_rx1) ? one : -one);
            branch_metric = m;
        end
    endfunction

    always @* begin
        // Unconditional defaults for every combinational temporary so Quartus
        // does not infer latches when in_valid is low.
        prev_state    = {STATE_W{1'b0}};
        dst_state     = {STATE_W{1'b0}};
        in_bit        = 1'b0;
        expected_bits = 2'b0;
        cand_metric   = {METRIC_W{1'b0}};
        best_state    = {STATE_W{1'b0}};
        best_metric   = METRIC_MIN;
        tb_state      = {STATE_W{1'b0}};
        tb_bits       = {TB_DEPTH{1'b0}};
        min_metric    = METRIC_MIN;
        min_offset_next = {METRIC_W{1'b0}};
        b             = 0;
        for (s = 0; s < NUM_STATES; s = s + 1) begin
            best_prev[s] = {STATE_W{1'b0}};
            best_bit[s]  = 1'b0;
        end

        for (s = 0; s < NUM_STATES; s = s + 1) begin
            next_path_metric[s] = path_metric[s];
        end

        for (d = 0; d < TB_DEPTH; d = d + 1) begin
            for (s = 0; s < NUM_STATES; s = s + 1) begin
                next_survivor_prev[d][s] = survivor_prev[d][s];
                next_survivor_bit[d][s]  = survivor_bit[d][s];
            end
        end

        next_sym_count     = sym_count;
        next_decoded_valid = 1'b0;
        next_decoded_bit   = decoded_bit;

        if (in_valid_eff) begin // PIPELINE: gated by registered in_valid when PIPELINE=1
            for (s = 0; s < NUM_STATES; s = s + 1) begin
                next_path_metric[s] = METRIC_MIN;
                best_prev[s]        = 0;
                best_bit[s]         = 1'b0;
            end

            for (s = 0; s < NUM_STATES; s = s + 1) begin
                prev_state = s[STATE_W-1:0];
                for (b = 0; b < 2; b = b + 1) begin
                    in_bit = b[0];
                    dst_state = {in_bit, prev_state[1]};
                    expected_bits = enc_out(prev_state, in_bit);
                    if (path_metric[prev_state] != METRIC_MIN) begin
                        // PIPELINE: rx0_eff/rx1_eff = registered inputs when PIPELINE=1
                        cand_metric = path_metric[prev_state] + branch_metric(rx0_eff, rx1_eff, expected_bits);

                        if (cand_metric > next_path_metric[dst_state]) begin
                            next_path_metric[dst_state] = cand_metric;
                            best_prev[dst_state]        = prev_state;
                            best_bit[dst_state]         = in_bit;
                        end
                    end
                end
            end

            for (d = TB_DEPTH-1; d > 0; d = d - 1) begin
                for (s = 0; s < NUM_STATES; s = s + 1) begin
                    next_survivor_prev[d][s] = survivor_prev[d-1][s];
                    next_survivor_bit[d][s]  = survivor_bit[d-1][s];
                end
            end

            for (s = 0; s < NUM_STATES; s = s + 1) begin
                next_survivor_prev[0][s] = best_prev[s];
                next_survivor_bit[0][s]  = best_bit[s];
            end

            // ============================================================
            // === NORMALIZE (apply): subtract last cycle's registered min
            // The min reduction runs in parallel with ACS (see the block
            // outside this if), and its result is registered into
            // min_offset_q.  Subtracting the same constant from every
            // reachable state preserves argmax exactly, so decoded
            // output is bit-exact to NORMALIZE=0 on short runs.
            // ============================================================
            if (NORMALIZE != 0) begin
                for (s = 0; s < NUM_STATES; s = s + 1) begin
                    if (next_path_metric[s] != METRIC_MIN) begin
                        next_path_metric[s] = next_path_metric[s] - min_offset_q;
                    end
                end
            end
            // ============================================================

            best_state  = 0;
            best_metric = next_path_metric[0];
            for (s = 1; s < NUM_STATES; s = s + 1) begin
                if (next_path_metric[s] > best_metric) begin
                    best_metric = next_path_metric[s];
                    best_state  = s[STATE_W-1:0];
                end
            end

            tb_state = best_state;
            for (d = 0; d < TB_DEPTH; d = d + 1) begin
                tb_bits[d] = next_survivor_bit[d][tb_state];
                tb_state   = next_survivor_prev[d][tb_state];
            end

            next_decoded_bit = tb_bits[TB_DEPTH-1];
            if (sym_count >= (TB_DEPTH-1)) begin
                next_decoded_valid = 1'b1;
            end

            if (sym_count < TB_DEPTH) begin
                next_sym_count = sym_count + 1'b1;
            end
        end

        // ================================================================
        // === NORMALIZE (compute): parallel min over registered metrics ==
        // Runs every cycle on the *registered* path_metric[] values, so
        // its 4-way reduction is NOT in series with the ACS comparator.
        // Result is captured into min_offset_q on the next clock edge
        // and consumed by the subtract block above on the cycle after
        // that, giving a one-cycle-delayed offset.  Drift is bounded
        // by per-symbol branch metric range (a few units), well inside
        // the 16-bit signed headroom.
        // ================================================================
        if (NORMALIZE != 0) begin
            min_metric = METRIC_MIN;
            for (s = 0; s < NUM_STATES; s = s + 1) begin
                if (path_metric[s] != METRIC_MIN) begin
                    if (min_metric == METRIC_MIN ||
                        path_metric[s] < min_metric) begin
                        min_metric = path_metric[s];
                    end
                end
            end
            if (min_metric != METRIC_MIN) begin
                min_offset_next = min_metric;
            end
        end
        // ================================================================
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (s = 0; s < NUM_STATES; s = s + 1) begin
                if (s == 0) begin
                    path_metric[s] <= 0;
                end else begin
                    path_metric[s] <= METRIC_MIN;
                end
            end

            for (d = 0; d < TB_DEPTH; d = d + 1) begin
                for (s = 0; s < NUM_STATES; s = s + 1) begin
                    survivor_prev[d][s] <= 0;
                    survivor_bit[d][s]  <= 1'b0;
                end
            end

            sym_count     <= 0;
            decoded_valid <= 1'b0;
            decoded_bit   <= 1'b0;
            min_offset_q  <= {METRIC_W{1'b0}};
        end else begin
            for (s = 0; s < NUM_STATES; s = s + 1) begin
                path_metric[s] <= next_path_metric[s];
            end
            min_offset_q <= min_offset_next;
            for (d = 0; d < TB_DEPTH; d = d + 1) begin
                for (s = 0; s < NUM_STATES; s = s + 1) begin
                    survivor_prev[d][s] <= next_survivor_prev[d][s];
                    survivor_bit[d][s]  <= next_survivor_bit[d][s];
                end
            end

            sym_count     <= next_sym_count;
            decoded_valid <= next_decoded_valid;
            decoded_bit   <= next_decoded_bit;
        end
    end

endmodule
