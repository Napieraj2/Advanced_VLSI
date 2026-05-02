`timescale 1ns/1ps

// =============================================================================
// tb_viterbi_hard_decoder_cosim
// -----------------------------------------------------------------------------
// File-driven cosim testbench for viterbi_hard_decoder.  Sister of
// tb_viterbi_soft_decoder_cosim.v: reads single-bit hard-sliced samples from
// "stim_hard.txt" (one "rx0 rx1" pair per line, each 0 or 1) and writes one
// decoded data bit per payload bit to "dec_hard.txt".
//
// Hard-decoder path metrics live in {-2, 0, +2}, so the 16-bit signed path
// metric does not saturate; each Eb/N0 point is driven as a single continuous
// N_BITS_PER_POINT-bit run with one cold-start reset at the top of the point.
// =============================================================================

module tb_viterbi_hard_decoder_cosim;

    parameter TB_DEPTH         = 12;
    parameter METRIC_W         = 16;
    parameter PIPELINE         = 1;
    localparam LATENCY         = (PIPELINE != 0) ? 1 : 0;

    parameter integer N_BITS_PER_POINT = 10000;
    parameter integer TAIL_BITS        = 2;
    parameter integer TOTAL_BITS       = N_BITS_PER_POINT + TAIL_BITS;
    parameter integer N_POINTS         = 9;

    // -------------------------------------------------------------------------
    reg  clk      = 1'b0;
    reg  rst_n    = 1'b0;
    reg  in_valid = 1'b0;
    reg  rx0      = 1'b0;
    reg  rx1      = 1'b0;
    wire decoded_valid;
    wire decoded_bit;

    always #5 clk = ~clk;

    viterbi_hard_decoder #(
        .TB_DEPTH (TB_DEPTH),
        .METRIC_W (METRIC_W),
        .PIPELINE (PIPELINE)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .in_valid      (in_valid),
        .rx0           (rx0),
        .rx1           (rx1),
        .decoded_valid (decoded_valid),
        .decoded_bit   (decoded_bit)
    );

    // -------------------------------------------------------------------------
    integer fin, fout;
    integer p, k;
    integer b0, b1, scan;
    integer dec_count;
    integer dec_buf [0:TOTAL_BITS+TB_DEPTH+LATENCY+16];

    initial begin
        fin  = $fopen("stim_hard.txt", "r");
        if (fin == 0) begin
            $display("ERROR: could not open stim_hard.txt");
            $finish;
        end
        fout = $fopen("dec_hard.txt", "w");
        if (fout == 0) begin
            $display("ERROR: could not open dec_hard.txt for writing");
            $finish;
        end

        for (p = 0; p < N_POINTS; p = p + 1) begin
            rst_n    = 1'b0;
            in_valid = 1'b0;
            rx0      = 1'b0;
            rx1      = 1'b0;
            @(posedge clk); @(posedge clk); @(posedge clk); @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);

            dec_count = 0;

            for (k = 0; k < TOTAL_BITS; k = k + 1) begin
                scan = $fscanf(fin, "%d %d\n", b0, b1);
                if (scan != 2) begin
                    $display("ERROR: short read at point=%0d sym=%0d", p, k);
                    $finish;
                end
                in_valid = 1'b1;
                rx0      = b0[0];
                rx1      = b1[0];
                @(posedge clk);
                if (decoded_valid) begin
                    dec_buf[dec_count] = decoded_bit;
                    dec_count = dec_count + 1;
                end
            end

            in_valid = 1'b0;
            rx0      = 1'b0;
            rx1      = 1'b0;
            for (k = 0; k < TB_DEPTH + LATENCY + 4; k = k + 1) begin
                @(posedge clk);
                if (decoded_valid) begin
                    dec_buf[dec_count] = decoded_bit;
                    dec_count = dec_count + 1;
                end
            end

            for (k = 0; k < N_BITS_PER_POINT; k = k + 1) begin
                if (k < dec_count) $fwrite(fout, "%0d\n", dec_buf[k]);
                else               $fwrite(fout, "X\n");
            end
        end

        $fclose(fin);
        $fclose(fout);
        $display("tb_viterbi_hard_decoder_cosim: done (%0d points, %0d bits/point)",
                 N_POINTS, N_BITS_PER_POINT);
        $finish;
    end

endmodule
