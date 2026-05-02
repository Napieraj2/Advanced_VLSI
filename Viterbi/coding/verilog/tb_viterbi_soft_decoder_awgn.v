`timescale 1ns/1ps

// =============================================================================
// tb_viterbi_soft_decoder_awgn
// -----------------------------------------------------------------------------
// AWGN BER characterization testbench for viterbi_soft_decoder.
//
// Replaces the bounded-uniform noise in tb_viterbi_soft_decoder.v with a
// proper Gaussian channel model built from two 32-bit Galois LFSRs feeding
// a Box-Muller transform (cached pair).  This lets the hardware decoder be
// exercised against the same AWGN curves the MATLAB study sweeps with
// vitdec(), so the RTL and the MATLAB design model can be compared
// end-to-end.
//
// Channel model (BPSK over real AWGN):
//   tx amplitude per coded bit   : +/- NOM_LEVEL
//   noise variance per coordinate: sigma^2 = N0/2
//   relationship                 : Es = NOM_LEVEL^2,  Es/N0 = Eb/N0 - 3 dB
//                                  (rate 1/2 code)
//   sigma = NOM_LEVEL / sqrt(2 * 10^((EbN0_dB - 3.0103)/10))
//
// IMPORTANT: viterbi_soft_decoder uses a 16-bit signed path metric without
// internal normalization.  At NOM_LEVEL = 48 each correctly-decoded symbol
// can contribute up to ~2*127 = 254 to the path metric (soft saturation),
// so the metric overflows after a few hundred symbols of an uninterrupted
// run.  To stay clear of that overflow, this testbench runs each Eb/N0
// point as TRIALS_PER_POINT independent trials of N_BITS_PER_TRIAL data
// bits each, with a full DUT reset between trials, and accumulates errors
// across the trials.  This is a property of the existing DUT, not the
// channel model.
//
// The Box-Muller block uses $ln/$sqrt/$cos/$sin (simulation-only system
// functions); only the LFSRs are bit-exact hardware-style logic.  The
// noise source is a verification model, not synthesizable RTL, so it
// stays inside the testbench.
// =============================================================================

module tb_viterbi_soft_decoder_awgn;

    // -------------------------------------------------------------------------
    // DUT parameters
    // -------------------------------------------------------------------------
    parameter SOFT_W    = 8;
    parameter TB_DEPTH  = 12;
    parameter METRIC_W  = 16;
    parameter PIPELINE  = 1;
    localparam LATENCY  = (PIPELINE != 0) ? 2 : 0;

    // -------------------------------------------------------------------------
    // Channel / sweep configuration
    // -------------------------------------------------------------------------
    parameter integer NOM_LEVEL          = 48;     // BPSK soft amplitude
    parameter integer SOFT_MAX           =  127;
    parameter integer SOFT_MIN           = -127;
    parameter integer N_POINTS           = 9;
    // Path-metric overflow constraint (METRIC_W = 16, no normalization in
    // the DUT): keep N_BITS_PER_TRIAL * 2 * SOFT_MAX comfortably below
    // 2^15 - 1.  At SOFT_MAX = 127 this means N_BITS_PER_TRIAL <= ~128.
    parameter integer N_BITS_PER_TRIAL   = 100;
    parameter integer TRIALS_PER_POINT   = 50;     // -> 5000 bits/point
    parameter integer TAIL_BITS          = 2;
    parameter integer TOTAL_BITS         = N_BITS_PER_TRIAL + TAIL_BITS;

    // BER pass threshold for the high-SNR point (last entry in EBN0_TENTHS).
    // 5e-3 is loose enough to absorb the modest sample size at 8 dB Eb/N0
    // (theoretical soft BER << 1e-6, so any non-zero BER here is a fluke).
    parameter real    BER_PASS_THRESHOLD = 5.0e-3;

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
    reg                       clk;
    reg                       rst_n;
    reg                       in_valid;
    reg signed [SOFT_W-1:0]   soft0;
    reg signed [SOFT_W-1:0]   soft1;
    wire                      decoded_valid;
    wire                      decoded_bit;

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
    // Clock
    // -------------------------------------------------------------------------
    initial clk = 1'b0;
    always  #5 clk = ~clk;   // 100 MHz

    initial begin
        $dumpfile("tb_viterbi_soft_decoder_awgn.vcd");
        $dumpvars(0, tb_viterbi_soft_decoder_awgn);
    end

    // -------------------------------------------------------------------------
    // Encoder reference (matches viterbi_soft_decoder enc_out)
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
    // LFSR-based Box-Muller Gaussian source
    // -------------------------------------------------------------------------
    // Two 32-bit Galois LFSRs (CRC-32 polynomial) feed independent uniform
    // streams.  Box-Muller pairs them into N(0,1) samples and caches the
    // unused half of each pair.
    reg [31:0] lfsr_a;
    reg [31:0] lfsr_b;
    real       cached_z;
    integer    have_cached;

    localparam [31:0] LFSR_POLY = 32'h04C11DB7;

    function [31:0] lfsr_step;
        input [31:0] s;
        begin
            // Galois form (left-shift): shift in 0; XOR poly when MSB was 1.
            lfsr_step = (s[31]) ? ({s[30:0], 1'b0} ^ LFSR_POLY)
                                : ({s[30:0], 1'b0});
        end
    endfunction

    // Returns a uniform real in (0, 1] from the lower 31 bits of `s`.
    function real lfsr_to_unit;
        input [31:0] s;
        begin
            // (s[30:0] + 1) / 2^31 -> never zero, so $ln() is always defined.
            lfsr_to_unit = (s[30:0] + 1.0) / 2147483648.0;
        end
    endfunction

    // Draw one N(0,1) sample.  Side effects on lfsr_a/lfsr_b/cached_z/
    // have_cached are intentional and isolated to the testbench.
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

    // Saturate-and-quantize a real soft level into signed SOFT_W.
    function signed [SOFT_W-1:0] sat_quantize;
        input real x;
        integer xi;
        begin
            xi = $rtoi(x);
            if (xi >  SOFT_MAX) xi = SOFT_MAX;
            if (xi <  SOFT_MIN) xi = SOFT_MIN;
            sat_quantize = xi;
        end
    endfunction

    // -------------------------------------------------------------------------
    // Per-trial state shared with the capture block
    // -------------------------------------------------------------------------
    integer cur_point;
    integer cur_trial;
    integer bit_idx;          // decoded-bit counter for the current trial
    integer trial_errs;       // error counter for the current trial
    reg     capture_en;       // gate the capture block to the active trial

    reg     tx_bits [0:TOTAL_BITS-1];

    // -------------------------------------------------------------------------
    // Capture block: compare decoded bits against tx_bits for the active trial
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
    // One trial at a given Eb/N0 point.  Resets the DUT, drives a fresh
    // message, and reports trial bit count + error count.
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
            // Fresh message for this trial.
            for (i = 0; i < N_BITS_PER_TRIAL; i = i + 1) begin
                tx_bits[i] = ($random & 1);
            end
            for (i = N_BITS_PER_TRIAL; i < TOTAL_BITS; i = i + 1) begin
                tx_bits[i] = 1'b0;
            end

            // Reset DUT and capture state for this trial.
            rst_n       = 1'b0;
            in_valid    = 1'b0;
            soft0       = 0;
            soft1       = 0;
            enc_state   = 2'b00;
            cur_point   = p_idx;
            cur_trial   = t_idx;
            bit_idx     = 0;
            trial_errs  = 0;
            capture_en  = 1'b0;

            repeat (4) @(posedge clk);
            rst_n      = 1'b1;
            capture_en = 1'b1;

            // Drive coded symbols + AWGN.
            for (i = 0; i < TOTAL_BITS; i = i + 1) begin
                coded     = enc_out(enc_state, tx_bits[i]);
                enc_state = {tx_bits[i], enc_state[1]};

                get_gaussian(g0);
                get_gaussian(g1);

                lvl0 = (coded[1] ? NOM_LEVEL : -NOM_LEVEL) + sigma * g0;
                lvl1 = (coded[0] ? NOM_LEVEL : -NOM_LEVEL) + sigma * g1;

                @(negedge clk);
                in_valid = 1'b1;
                soft0    = sat_quantize(lvl0);
                soft1    = sat_quantize(lvl1);
            end

            // Drain so the last data bits walk out of traceback.
            for (k = 0; k < TB_DEPTH + 4 + LATENCY; k = k + 1) begin
                get_gaussian(g0);
                get_gaussian(g1);
                @(negedge clk);
                in_valid = 1'b1;
                soft0    = sat_quantize(-NOM_LEVEL + sigma * g0);
                soft1    = sat_quantize(-NOM_LEVEL + sigma * g1);
            end

            @(negedge clk);
            in_valid = 1'b0;

            // Allow remaining decoded bits to commit.
            repeat (TB_DEPTH + 8) @(posedge clk);

            capture_en = 1'b0;

            // Only the first N_BITS_PER_TRIAL decoded bits carry the random
            // payload; the tail bits are forced zeros we transmitted.
            trial_bits_used = (bit_idx > N_BITS_PER_TRIAL) ? N_BITS_PER_TRIAL
                                                           : bit_idx;
            trial_err_count = trial_errs;
        end
    endtask

    // -------------------------------------------------------------------------
    // One full Eb/N0 point: TRIALS_PER_POINT trials, accumulate errors.
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
            // Reseed LFSRs deterministically per point so points are
            // independent but each run is reproducible.
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
    // Top-level orchestration: build sweep grid, run each point, print table.
    // -------------------------------------------------------------------------
    integer p;
    real    ebn0_db;
    real    esn0_db;
    real    sigma;
    integer last_idx;
    real    last_ber;

    initial begin : main
        integer ii;
        // Eb/N0 grid: 0.0, 1.0, 2.0, ..., 8.0 dB
        for (ii = 0; ii < N_POINTS; ii = ii + 1) begin
            EBN0_TENTHS[ii] = ii * 10;
        end

        $display("==============================================================");
        $display(" Viterbi soft decoder -- AWGN BER sweep (LFSR Box-Muller)");
        $display("   PIPELINE         = %0d", PIPELINE);
        $display("   NOM_LEVEL        = %0d", NOM_LEVEL);
        $display("   N_BITS_PER_TRIAL = %0d", N_BITS_PER_TRIAL);
        $display("   TRIALS_PER_POINT = %0d", TRIALS_PER_POINT);
        $display("   bits/point       = %0d",
                 N_BITS_PER_TRIAL * TRIALS_PER_POINT);
        $display("==============================================================");

        for (p = 0; p < N_POINTS; p = p + 1) begin
            ebn0_db = EBN0_TENTHS[p] / 10.0;
            esn0_db = ebn0_db - 3.0102999566;             // 10*log10(rate)
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
