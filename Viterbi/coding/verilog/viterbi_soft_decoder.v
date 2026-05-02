`timescale 1ns/1ps

module viterbi_soft_decoder #(
    parameter SOFT_W   = 8,
    parameter TB_DEPTH = 12,
    parameter METRIC_W = 16
) (
    input                           clk,
    input                           rst_n,
    input                           in_valid,
    input      signed [SOFT_W-1:0]  soft0,
    input      signed [SOFT_W-1:0]  soft1,
    output reg                      decoded_valid,
    output reg                      decoded_bit
);

    localparam NUM_STATES = 4;
    localparam STATE_W    = 2;
    localparam signed [METRIC_W-1:0] METRIC_MIN = -((1 << (METRIC_W-1)) - 1);

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

    integer s;
    integer d;
    integer b;

    function [1:0] enc_out;
        input [1:0] prev_state;
        input       in_bit;
        reg c0;
        reg c1;
        begin
            // Rate 1/2, K=3 encoder with generators (7,5)
            c0 = in_bit ^ prev_state[1] ^ prev_state[0];
            c1 = in_bit ^ prev_state[0];
            enc_out = {c0, c1};
        end
    endfunction

    function signed [METRIC_W-1:0] branch_metric;
        input signed [SOFT_W-1:0] rx0;
        input signed [SOFT_W-1:0] rx1;
        input [1:0] expected;
        reg signed [METRIC_W-1:0] m;
        begin
            m = 0;
            m = m + (expected[1] ? rx0 : -rx0);
            m = m + (expected[0] ? rx1 : -rx1);
            branch_metric = m;
        end
    endfunction

    always @* begin
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

        if (in_valid) begin
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
                        cand_metric = path_metric[prev_state] + branch_metric(soft0, soft1, expected_bits);

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
        end else begin
            for (s = 0; s < NUM_STATES; s = s + 1) begin
                path_metric[s] <= next_path_metric[s];
            end
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
