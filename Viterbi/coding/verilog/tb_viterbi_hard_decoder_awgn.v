`timescale 1ns/1ps

// =============================================================================
// tb_viterbi_hard_decoder_awgn
// -----------------------------------------------------------------------------
// AWGN BER characterization testbench for viterbi_hard_decoder.
//
// Same channel model as tb_viterbi_soft_decoder_awgn.v: each coded bit is
// modulated to +/- NOM_LEVEL and perturbed by N(0, sigma^2) noise from an
// LFSR-driven Box-Muller source.  The receiver is a hard slicer:
//
//     rx_bit = (level + noise) >= 0 ? 1 : 0
//
// This drives the existing single-bit rx0/rx1 ports of viterbi_hard_decoder
// over the same Gaussian channel the soft testbench uses, so the soft and
// hard variants can be characterized end-to-end on the same noise process.
//
// Channel model (BPSK over real AWGN):
//   tx amplitude per coded bit   : +/- NOM_LEVEL
//   noise variance per coordinate: sigma^2 = N0/2
//   relationship                 : Es = NOM_LEVEL^2,  Es/N0 = Eb/N0 - 3 dB
//                                  (rate 1/2 code)
//   sigma = NOM_LEVEL / sqrt(2 * 10^((EbN0_dB - 3.0103)/10))
//
// Like the soft testbench, each Eb/N0 point is run as TRIALS_PER_POINT
// independent trials of N_BITS_PER_TRIAL bits with a full DUT reset
// between trials.  The hard decoder's branch metric is bounded to {-2,0,+2}
// per symbol so the 16-bit signed path metric does not saturate even for
// long runs, but the trial structure is kept for symmetry with the soft
// testbench so the two BER tables are directly comparable.
// =============================================================================

module tb_viterbi_hard_decoder_awgn;

    // -------------------------------------------------------------------------
    // DUT parameters
    // -------------------------------------------------------------------------
    parameter TB_DEPTH  = 12;
    parameter METRIC_W  = 16;
    parameter PIPELINE  = 1;
    localparam LATENCY  = (PIPELINE != 0) ? 1 : 0;

    // -------------------------------------------------------------------------
    // Channel / sweep configuration (kept identical to the soft AWGN TB)
    // -------------------------------------------------------------------------
    parameter integer NOM_LEVEL          = 48;     // BPSK soft amplitude
    parameter integer N_POINTS           = 9;
    parameter integer N_BITS_PER_TRIAL   = 100;
    parameter integer TRIALS_PER_POINT   = 50;     // -> 5000 bits/point
    parameter integer TAIL_BITS          = 2;
    parameter integer TOTAL_BITS         = N_BITS_PER_TRIAL + TAIL_BITS;

    // BER pass threshold for the high-SNR point.  The hard decoder loses
    // ~2 dB to the soft decoder, so the threshold is loosened accordingly.
    parameter real    BER_PASS_THRESHOLD = 1.0e-2;

    // Eb/N0 grid in tenths of dB.
    integer EBN0_TENTHS [0:N_POINTS-1];

    // -------------------------------------------------------------------------
    // Per-point bookkeeping
    // -------------------------------------------------------------------------
    integer errs    [0:N_POINTS-1];
    integer counted [0:N_POINTS-1];
    real    ber     [0:N_POINTS-1];
    real    sigma_pt[0:N_POINTS-1];

    // -------------------------------------------------------------------------
    // DUT I/O
    // -------------------------------------------------------------------------
    reg   clk;
    reg   rst_n;
    reg   in_valid;
    reg   rx0;
    reg   rx1;
    wire  decoded_valid;
    wire  decoded_bit;

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
    // Clock
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always  #5 clk = ~clk;   // 100 MHz

    initial begin
        $dumpfile("tb_viterbi_hard_decoder_awgn.vcd");
        $dumpvars(0, tb_viterbi_hard_decoder_awgn);
    end

    // -------------------------------------------------------------------------
    // Encoder reference (matches viterbi_hard_decoder enc_out)
    // -------------------------------------------------------------------------
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

    // -------------------------------------------------------------------------
    // LFSR-based Box-Muller Gaussian source (identical to soft AWGN TB)
    // -------------------------------------------------------------------------
    reg [31:0] lfsr_a;
    reg [31:0] lfsr_b;
    real       cached_z;
    integer    have_cached;

    localparam [31:0] LFSR_POLY = 32'h04C11DB7;

    function [31:0] lfsr_step;
        input [31:0] s;
        begin
            lfsr_step = (s[31]) ? ({s[30:0], 1'b0} ^ LFSR_POLY)
                                : ({s[30:0], 1'b0});
        end
    endfunction

    function real lfsr_to_unit;
        input [31:0] s;
        begin
            lfsr_to_unit = (s[30:0] + 1.0) / 2147483648.0;
        end
    endfunction

    task get_gaussian;
        output real z;
        real u1, u2, r, theta;
        begin
            if (have_cached) begin
                z           = cached_z;
                have_cached = 0;
            end else begin
                lfsr_a = lfsr_step(lfsr_a);
                lfsr_b = lfsr_step(lfsr_b);
                u1     = lfsr_to_unit(lfsr_a);
                u2     = lfsr_to_unit(lfsr_b);
                r      = $sqrt(-2.0 * $ln(u1));
                theta  = 2.0 * 3.141592653589793 * u2;
                z           = r * $cos(theta);
                cached_z    = r * $sin(theta);
                have_cached = 1;
            end
        end
    endtask

    // Hard slicer on a real soft level -> 1 bit (1 if level >= 0).
    function bit_slice;
        input real x;
        begin
            bit_slice = (x >= 0.0) ? 1'b1 : 1'b0;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Per-trial state shared with the capture block
    // -------------------------------------------------------------------------
    integer cur_point;
    integer cur_trial;
    integer bit_idx;
    integer trial_errs;
    reg     capture_en;

    reg     tx_bits [0:TOTAL_BITS-1];

    // -------------------------------------------------------------------------
    // Capture block
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && capture_en && decoded_valid && (bit_idx < TOTAL_BITS)) begin
            if (decoded_bit !== tx_bits[bit_idx]) begin
                trial_errs <= trial_errs + 1;
            end
            bit_idx <= bit_idx + 1;
        end
    end

    // -------------------------------------------------------------------------
    // One trial at a given Eb/N0 point.
    // -------------------------------------------------------------------------
    task run_trial;
        input  integer p_idx;
        input  integer t_idx;
        input  real    sigma;
        output integer trial_bits_used;
        output integer trial_err_count;
        integer i, k;
        reg [1:0] enc_state;
        reg [1:0] coded;
        real      g0, g1;
        real      lvl0, lvl1;
        begin
            for (i = 0; i < N_BITS_PER_TRIAL; i = i + 1) begin
                tx_bits[i] = ($random & 1);
            end
            for (i = N_BITS_PER_TRIAL; i < TOTAL_BITS; i = i + 1) begin
                tx_bits[i] = 1'b0;
            end

            rst_n       = 1'b0;
            in_valid    = 1'b0;
            rx0         = 1'b0;
            rx1         = 1'b0;
            enc_state   = 2'b00;
            cur_point   = p_idx;
            cur_trial   = t_idx;
            bit_idx     = 0;
            trial_errs  = 0;
            capture_en  = 1'b0;

            repeat (4) @(posedge clk);
            rst_n      = 1'b1;
            capture_en = 1'b1;

            for (i = 0; i < TOTAL_BITS; i = i + 1) begin
                coded     = enc_out(enc_state, tx_bits[i]);
                enc_state = {tx_bits[i], enc_state[1]};

                get_gaussian(g0);
                get_gaussian(g1);

                lvl0 = (coded[1] ? NOM_LEVEL : -NOM_LEVEL) + sigma * g0;
                lvl1 = (coded[0] ? NOM_LEVEL : -NOM_LEVEL) + sigma * g1;

                @(negedge clk);
                in_valid = 1'b1;
                rx0      = bit_slice(lvl0);
                rx1      = bit_slice(lvl1);
            end

            for (k = 0; k < TB_DEPTH + 4 + LATENCY; k = k + 1) begin
                get_gaussian(g0);
                get_gaussian(g1);
                @(negedge clk);
                in_valid = 1'b1;
                rx0      = bit_slice(-NOM_LEVEL + sigma * g0);
                rx1      = bit_slice(-NOM_LEVEL + sigma * g1);
            end

            @(negedge clk);
            in_valid = 1'b0;

            repeat (TB_DEPTH + 8) @(posedge clk);

            capture_en = 1'b0;

            trial_bits_used = (bit_idx > N_BITS_PER_TRIAL) ? N_BITS_PER_TRIAL
                                                           : bit_idx;
            trial_err_count = trial_errs;
        end
    endtask

    // -------------------------------------------------------------------------
    // One full Eb/N0 point
    // -------------------------------------------------------------------------
    task run_point;
        input integer p_idx;
        input real    sigma;
        integer t;
        integer tb_used;
        integer tb_errs;
        integer total_bits;
        integer total_errs;
        begin
            lfsr_a      = 32'hDEADBEEF ^ (p_idx * 32'h9E3779B9);
            lfsr_b      = 32'h1BADF00D ^ (p_idx * 32'h7F4A7C15);
            have_cached = 0;
            cached_z    = 0.0;

            total_bits = 0;
            total_errs = 0;
            for (t = 0; t < TRIALS_PER_POINT; t = t + 1) begin
                run_trial(p_idx, t, sigma, tb_used, tb_errs);
                total_bits = total_bits + tb_used;
                total_errs = total_errs + tb_errs;
            end

            errs[p_idx]    = total_errs;
            counted[p_idx] = total_bits;
            ber[p_idx]     = (total_bits > 0) ? (total_errs * 1.0 / total_bits)
                                              : 1.0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Top-level orchestration
    // -------------------------------------------------------------------------
    integer p;
    real    ebn0_db;
    real    esn0_db;
    real    sigma;
    integer last_idx;
    real    last_ber;

    initial begin : main
        integer ii;
        for (ii = 0; ii < N_POINTS; ii = ii + 1) begin
            EBN0_TENTHS[ii] = ii * 10;
        end

        $display("==============================================================");
        $display(" Viterbi hard decoder -- AWGN BER sweep (LFSR Box-Muller)");
        $display("   PIPELINE         = %0d", PIPELINE);
        $display("   NOM_LEVEL        = %0d", NOM_LEVEL);
        $display("   N_BITS_PER_TRIAL = %0d", N_BITS_PER_TRIAL);
        $display("   TRIALS_PER_POINT = %0d", TRIALS_PER_POINT);
        $display("   bits/point       = %0d",
                 N_BITS_PER_TRIAL * TRIALS_PER_POINT);
        $display("==============================================================");

        for (p = 0; p < N_POINTS; p = p + 1) begin
            ebn0_db = EBN0_TENTHS[p] / 10.0;
            esn0_db = ebn0_db - 3.0102999566;
            sigma   = NOM_LEVEL / $sqrt(2.0 * (10.0 ** (esn0_db / 10.0)));
            sigma_pt[p] = sigma;

            run_point(p, sigma);

            $display("Eb/N0 = %4.1f dB | sigma = %7.3f | bits = %6d | errs = %6d | BER = %.3e",
                     ebn0_db, sigma, counted[p], errs[p], ber[p]);
        end

        $display("--------------------------------------------------------------");
        $display(" Summary");
        $display("--------------------------------------------------------------");
        $display(" Eb/N0 (dB) |   sigma   |   bits  |   errs  |    BER");
        for (p = 0; p < N_POINTS; p = p + 1) begin
            $display("   %5.1f    | %8.3f  | %7d | %7d | %.3e",
                     EBN0_TENTHS[p] / 10.0, sigma_pt[p], counted[p],
                     errs[p], ber[p]);
        end

        last_idx = N_POINTS - 1;
        last_ber = ber[last_idx];
        if (last_ber <= BER_PASS_THRESHOLD) begin
            $display("PASS  (BER @ %4.1f dB = %.3e <= %.3e)",
                     EBN0_TENTHS[last_idx] / 10.0, last_ber, BER_PASS_THRESHOLD);
        end else begin
            $display("FAIL  (BER @ %4.1f dB = %.3e >  %.3e)",
                     EBN0_TENTHS[last_idx] / 10.0, last_ber, BER_PASS_THRESHOLD);
        end

        $finish;
    end

endmodule
