`timescale 1ns/1ps

module tb_viterbi_hard_decoder;

    parameter TB_DEPTH  = 12;
    parameter MSG_BITS  = 40;
    parameter TAIL_BITS = 2;
    parameter TOTAL_BITS = MSG_BITS + TAIL_BITS;
    // PIPELINE additions: matches DUT PIPELINE parameter; LATENCY is the
    // extra decode latency in clock cycles (0 baseline, 1 pipelined).
    parameter PIPELINE  = 0;
    localparam LATENCY  = (PIPELINE != 0) ? 1 : 0;

    reg clk;
    reg rst_n;
    reg in_valid;
    reg rx0;
    reg rx1;
    wire decoded_valid;
    wire decoded_bit;

    reg tx_bits [0:TOTAL_BITS-1];
    reg [1:0] enc_state;

    integer out_count;
    integer err_count;
    integer i;

    reg [1:0] coded;
    reg [1:0] noisy_coded;

    viterbi_hard_decoder #(
        .TB_DEPTH(TB_DEPTH),
        .METRIC_W(16),
        .PIPELINE(PIPELINE) // PIPELINE additions
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .rx0(rx0),
        .rx1(rx1),
        .decoded_valid(decoded_valid),
        .decoded_bit(decoded_bit)
    );

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

    function [1:0] apply_channel_errors;
        input [1:0] clean_bits;
        reg [1:0] v;
        integer r;
        begin
            v = clean_bits;
            r = $random % 100;
            if (r < 0) r = -r;
            if (r < 8) v[1] = ~v[1];

            r = $random % 100;
            if (r < 0) r = -r;
            if (r < 8) v[0] = ~v[0];

            apply_channel_errors = v;
        end
    endfunction

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $dumpfile("tb_viterbi_hard_decoder.vcd");
        $dumpvars(0, tb_viterbi_hard_decoder);
    end

    initial begin
        rst_n     = 1'b0;
        in_valid  = 1'b0;
        rx0       = 1'b0;
        rx1       = 1'b0;
        enc_state = 0;
        out_count = 0;
        err_count = 0;

        for (i = 0; i < MSG_BITS; i = i + 1) begin
            tx_bits[i] = ($random & 1);
        end
        for (i = MSG_BITS; i < TOTAL_BITS; i = i + 1) begin
            tx_bits[i] = 1'b0;
        end

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        for (i = 0; i < TOTAL_BITS; i = i + 1) begin
            coded = enc_out(enc_state, tx_bits[i]);
            enc_state = {tx_bits[i], enc_state[1]};
            noisy_coded = apply_channel_errors(coded);

            @(negedge clk);
            in_valid = 1'b1;
            rx0      = noisy_coded[1];
            rx1      = noisy_coded[0];
        end

        // Feed additional symbols so traceback can flush the last bits.
        // PIPELINE additions: extend flush by LATENCY to absorb extra latency.
        for (i = 0; i < TB_DEPTH + 4 + LATENCY; i = i + 1) begin
            @(negedge clk);
            in_valid = 1'b1;
            rx0      = 1'b0;
            rx1      = 1'b0;
        end

        @(negedge clk);
        in_valid = 1'b0;

        repeat (10) @(posedge clk);

        $display("Decoded bits checked: %0d", out_count);
        $display("Bit errors: %0d", err_count);
        if (err_count == 0) begin
            $display("PASS");
        end else begin
            $display("FAIL");
        end

        $finish;
    end

    always @(posedge clk) begin
        if (rst_n && decoded_valid && (out_count < TOTAL_BITS)) begin
            if (decoded_bit !== tx_bits[out_count]) begin
                err_count <= err_count + 1;
            end
            out_count <= out_count + 1;
        end
    end

endmodule



