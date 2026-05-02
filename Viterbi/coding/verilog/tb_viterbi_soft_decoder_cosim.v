`timescale 1ns/1ps

// =============================================================================
// tb_viterbi_soft_decoder_cosim
// -----------------------------------------------------------------------------
// File-driven cosim testbench for viterbi_soft_decoder.
//
// Reads pre-generated soft samples from "stim_soft.txt" (one "s0 s1" pair per
// line, decimal int8 in the range [-127, +127]) and writes one decoded data
// bit per payload bit to "dec_soft.txt".
//
// The stimulus file is produced by cosim_rtl_ber_sweep.m, which mirrors the
// Simulink channel chain (BPSK + AWGN + 8-bit signed soft quantization) so
// that the RTL is exercised against the *same* channel model the toolbox
// Viterbi block sees in Viterbi_Simulink_Model.slx.
//
// With NORMALIZE = 1 in viterbi_soft_decoder.v, the 16-bit signed path
// metric is rescaled every ACS step and cannot saturate, so each Eb/N0
// point is driven as a single continuous N_BITS_PER_POINT-bit run with one
// cold-start reset at the top of the point.  No intra-point trial resets.
// =============================================================================

module tb_viterbi_soft_decoder_cosim;

    parameter SOFT_W           = 8;
    parameter TB_DEPTH         = 12;
    parameter METRIC_W         = 16;
    parameter PIPELINE         = 1;
    localparam LATENCY         = (PIPELINE != 0) ? 2 : 0;

    parameter integer N_BITS_PER_POINT = 10000;
    parameter integer TAIL_BITS        = 2;
    parameter integer TOTAL_BITS       = N_BITS_PER_POINT + TAIL_BITS;
    parameter integer N_POINTS         = 9;

    // -------------------------------------------------------------------------
    reg                          clk      = 1'b0;
    reg                          rst_n    = 1'b0;
    reg                          in_valid = 1'b0;
    reg  signed [SOFT_W-1:0]     soft0    = '0;
    reg  signed [SOFT_W-1:0]     soft1    = '0;
    wire                         decoded_valid;
    wire                         decoded_bit;

    always #5 clk = ~clk;

    viterbi_soft_decoder #(
        .SOFT_W   (SOFT_W),
        .TB_DEPTH (TB_DEPTH),
        .METRIC_W (METRIC_W),
        .PIPELINE (PIPELINE)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .in_valid      (in_valid),
        .soft0         (soft0),
        .soft1         (soft1),
        .decoded_valid (decoded_valid),
        .decoded_bit   (decoded_bit)
    );

    // -------------------------------------------------------------------------
    integer fin, fout;
    integer p, k;
    integer code0, code1, scan;
    integer dec_count;
    // Output buffer must hold every valid decoded bit emitted during one
    // point: TOTAL_BITS payload+tail symbols + drain.  Sized generously.
    integer dec_buf [0:TOTAL_BITS+TB_DEPTH+LATENCY+16];

    initial begin
        fin  = $fopen("stim_soft.txt", "r");
        if (fin == 0) begin
            $display("ERROR: could not open stim_soft.txt");
            $finish;
        end
        fout = $fopen("dec_soft.txt", "w");
        if (fout == 0) begin
            $display("ERROR: could not open dec_soft.txt for writing");
            $finish;
        end

        for (p = 0; p < N_POINTS; p = p + 1) begin
            // ---- DUT cold-start reset (once per Eb/N0 point) ---------------
            rst_n    = 1'b0;
            in_valid = 1'b0;
            soft0    = '0;
            soft1    = '0;
            @(posedge clk); @(posedge clk); @(posedge clk); @(posedge clk);
            rst_n = 1'b1;
            @(posedge clk);

            dec_count = 0;

            // ---- Drive TOTAL_BITS coded symbols continuously --------------
            for (k = 0; k < TOTAL_BITS; k = k + 1) begin
                scan = $fscanf(fin, "%d %d\n", code0, code1);
                if (scan != 2) begin
                    $display("ERROR: short read at point=%0d sym=%0d", p, k);
                    $finish;
                end
                in_valid = 1'b1;
                soft0    = code0[SOFT_W-1:0];
                soft1    = code1[SOFT_W-1:0];
                @(posedge clk);
                if (decoded_valid) begin
                    dec_buf[dec_count] = decoded_bit;
                    dec_count = dec_count + 1;
                end
            end

            // ---- Drain traceback + pipeline latency -----------------------
            in_valid = 1'b0;
            soft0    = '0;
            soft1    = '0;
            for (k = 0; k < TB_DEPTH + LATENCY + 4; k = k + 1) begin
                @(posedge clk);
                if (decoded_valid) begin
                    dec_buf[dec_count] = decoded_bit;
                    dec_count = dec_count + 1;
                end
            end

            // ---- Emit the first N_BITS_PER_POINT decoded data bits --------
            // The decoder emits in transmit order once decoded_valid is high;
            // the first N_BITS_PER_POINT outputs correspond to the payload,
            // the trailing ones are tail-bit decisions.
            for (k = 0; k < N_BITS_PER_POINT; k = k + 1) begin
                if (k < dec_count) $fwrite(fout, "%0d\n", dec_buf[k]);
                else               $fwrite(fout, "X\n");
            end
        end

        $fclose(fin);
        $fclose(fout);
        $display("tb_viterbi_soft_decoder_cosim: done (%0d points, %0d bits/point)",
                 N_POINTS, N_BITS_PER_POINT);
        $finish;
    end

endmodule
