// ============================================================================
// fir_parallel_L3.v — L=3 Polyphase Parallel FIR Filter
// ============================================================================
// Processes THREE input samples per clock and produces THREE output samples
// per clock, tripling throughput compared to fir_basic.
//
// Polyphase decomposition:
//   H(z) = H_0(z^3) + z^{-1} H_1(z^3) + z^{-2} H_2(z^3)
//
//   H_0: h(0), h(3), ..., h(189)   (64 taps)
//   H_1: h(1), h(4), ..., h(190)   (64 taps)
//   H_2: h(2), h(5), ..., h(191)   (64 taps)
//
// Symmetry exploitation:
//   1) h_0(j) = h_2(63-j)  — H_0 and H_2 are time-reverses → cross pre-add
//   2) h_1(j) = h_1(63-j)  — H_1 is self-symmetric → folded pre-add
//
// Multiplier count:
//   Naive 9 sub-filters × 64 taps = 576 multipliers
//   With cross pre-add (H_0/H_2):  3 outputs × 64 = 192  (h_0 coefficients)
//   With self-sym fold (H_1):       3 outputs × 32 =  96  (h_1 coefficients)
//   Total: 288 multipliers (50% reduction)
//
// 192-tap, Q20, 21-bit signed coefficients.
// Internal accumulation stays at 38 bits; the outputs saturate to 32 bits.
// ============================================================================

module fir_parallel_L3 #(
    parameter NUM_TAPS  = 192,
    parameter W_IN      = 16,
    parameter W_COEFF   = 21,
    parameter W_OUT     = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire signed [W_IN-1:0]  din_0,       // x(3k)
    input  wire signed [W_IN-1:0]  din_1,       // x(3k+1)
    input  wire signed [W_IN-1:0]  din_2,       // x(3k+2)
    input  wire                    din_valid,
    output reg  signed [W_OUT-1:0] dout_0,      // y(3k)
    output reg  signed [W_OUT-1:0] dout_1,      // y(3k+1)
    output reg  signed [W_OUT-1:0] dout_2,      // y(3k+2)
    output reg                     dout_valid
);

    localparam SUB_LEN  = NUM_TAPS / 3;    // 64
    localparam HALF_H1  = SUB_LEN / 2;     // 32

    localparam W_PREADD = W_IN + 1;        // 17
    localparam W_ACCUM  = (W_OUT > 38) ? W_OUT : 38;

    function integer clog2;
        input integer value;
        begin
            value = value - 1;
            for (clog2 = 0; value > 0; clog2 = clog2 + 1)
                value = value >> 1;
        end
    endfunction

    localparam signed [W_ACCUM-1:0] SAT_MAX = $signed({1'b0, {(W_OUT-1){1'b1}}});
    localparam signed [W_ACCUM-1:0] SAT_MIN = $signed({1'b1, {(W_OUT-1){1'b0}}});

    function signed [W_OUT-1:0] sat_output;
        input signed [W_ACCUM-1:0] value;
        begin
            if (value > SAT_MAX)
                sat_output = SAT_MAX[W_OUT-1:0];
            else if (value < SAT_MIN)
                sat_output = SAT_MIN[W_OUT-1:0];
            else
                sat_output = value[W_OUT-1:0];
        end
    endfunction
    localparam W_MULT   = W_PREADD + W_COEFF; // 38

    // =====================================================================
    //  Coefficient ROMs
    // =====================================================================
    // coeff_h0[0..63] = h(3j):  used for cross pre-add (H_0 + H_2)
    // coeff_h1[0..31] = h(3j+1) for j=0..31:  self-symmetric, 32 unique
    // =====================================================================
    reg signed [W_COEFF-1:0] coeff_h0 [0:SUB_LEN-1];
    reg signed [W_COEFF-1:0] coeff_h1 [0:HALF_H1-1];

    initial begin
        coeff_h0[ 0] =  21'sd153;      coeff_h0[ 1] =  21'sd737;
        coeff_h0[ 2] =  21'sd136;      coeff_h0[ 3] = -21'sd2619;
        coeff_h0[ 4] = -21'sd3102;     coeff_h0[ 5] =  21'sd311;
        coeff_h0[ 6] =  21'sd718;      coeff_h0[ 7] = -21'sd1850;
        coeff_h0[ 8] =  21'sd142;      coeff_h0[ 9] =  21'sd1789;
        coeff_h0[10] = -21'sd1839;     coeff_h0[11] = -21'sd737;
        coeff_h0[12] =  21'sd2896;     coeff_h0[13] = -21'sd1581;
        coeff_h0[14] = -21'sd2292;     coeff_h0[15] =  21'sd3972;
        coeff_h0[16] = -21'sd562;      coeff_h0[17] = -21'sd4519;
        coeff_h0[18] =  21'sd4672;     coeff_h0[19] =  21'sd1617;
        coeff_h0[20] = -21'sd7380;     coeff_h0[21] =  21'sd4497;
        coeff_h0[22] =  21'sd5503;     coeff_h0[23] = -21'sd10864;
        coeff_h0[24] =  21'sd2627;     coeff_h0[25] =  21'sd12345;
        coeff_h0[26] = -21'sd15380;    coeff_h0[27] = -21'sd3153;
        coeff_h0[28] =  21'sd27347;    coeff_h0[29] = -21'sd24192;
        coeff_h0[30] = -21'sd28292;    coeff_h0[31] =  21'sd132943;
        coeff_h0[32] =  21'sd216278;   coeff_h0[33] =  21'sd70338;
        coeff_h0[34] = -21'sd46466;    coeff_h0[35] = -21'sd493;
        coeff_h0[36] =  21'sd23969;    coeff_h0[37] = -21'sd14827;
        coeff_h0[38] = -21'sd5986;     coeff_h0[39] =  21'sd14263;
        coeff_h0[40] = -21'sd5350;     coeff_h0[41] = -21'sd6906;
        coeff_h0[42] =  21'sd8810;     coeff_h0[43] = -21'sd801;
        coeff_h0[44] = -21'sd6284;     coeff_h0[45] =  21'sd4993;
        coeff_h0[46] =  21'sd1474;     coeff_h0[47] = -21'sd4965;
        coeff_h0[48] =  21'sd2274;     coeff_h0[49] =  21'sd2368;
        coeff_h0[50] = -21'sd3435;     coeff_h0[51] =  21'sd474;
        coeff_h0[52] =  21'sd2395;     coeff_h0[53] = -21'sd2033;
        coeff_h0[54] = -21'sd565;      coeff_h0[55] =  21'sd1950;
        coeff_h0[56] = -21'sd1043;     coeff_h0[57] = -21'sd1237;
        coeff_h0[58] =  21'sd1239;     coeff_h0[59] = -21'sd891;
        coeff_h0[60] = -21'sd3513;     coeff_h0[61] = -21'sd1648;
        coeff_h0[62] =  21'sd626;      coeff_h0[63] =  21'sd540;
    end

    initial begin
        coeff_h1[ 0] =  21'sd317;      coeff_h1[ 1] =  21'sd802;
        coeff_h1[ 2] = -21'sd660;      coeff_h1[ 3] = -21'sd3315;
        coeff_h1[ 4] = -21'sd2148;     coeff_h1[ 5] =  21'sd1099;
        coeff_h1[ 6] = -21'sd240;      coeff_h1[ 7] = -21'sd1794;
        coeff_h1[ 8] =  21'sd1300;     coeff_h1[ 9] =  21'sd833;
        coeff_h1[10] = -21'sd2431;     coeff_h1[11] =  21'sd973;
        coeff_h1[12] =  21'sd2186;     coeff_h1[13] = -21'sd3120;
        coeff_h1[14] = -21'sd66;       coeff_h1[15] =  21'sd3986;
        coeff_h1[16] = -21'sd3384;     coeff_h1[17] = -21'sd2073;
        coeff_h1[18] =  21'sd6102;     coeff_h1[19] = -21'sd2748;
        coeff_h1[20] = -21'sd5348;     coeff_h1[21] =  21'sd8299;
        coeff_h1[22] = -21'sd530;      coeff_h1[23] = -21'sd10430;
        coeff_h1[24] =  21'sd10302;    coeff_h1[25] =  21'sd4702;
        coeff_h1[26] = -21'sd19145;    coeff_h1[27] =  21'sd11823;
        coeff_h1[28] =  21'sd18748;    coeff_h1[29] = -21'sd42822;
        coeff_h1[30] =  21'sd12648;    coeff_h1[31] =  21'sd185938;
    end

    // =====================================================================
    //  Delay lines (three polyphase streams)
    // =====================================================================
    //  dl_0: x_0 stream, 65 elements (needs index 0..63)
    //  dl_1: x_1 stream, 65 elements (needs index 0..64 for cross pre-adds)
    //  dl_2: x_2 stream, 65 elements (needs index 0..64 for cross pre-adds)
    // =====================================================================
    reg signed [W_IN-1:0] dl_0 [0:SUB_LEN];
    reg signed [W_IN-1:0] dl_1 [0:SUB_LEN];
    reg signed [W_IN-1:0] dl_2 [0:SUB_LEN];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i <= SUB_LEN; i = i + 1) begin
                dl_0[i] <= {W_IN{1'b0}};
                dl_1[i] <= {W_IN{1'b0}};
                dl_2[i] <= {W_IN{1'b0}};
            end
        end else if (din_valid) begin
            dl_0[0] <= din_0;
            dl_1[0] <= din_1;
            dl_2[0] <= din_2;
            for (i = 1; i <= SUB_LEN; i = i + 1) begin
                dl_0[i] <= dl_0[i-1];
                dl_1[i] <= dl_1[i-1];
                dl_2[i] <= dl_2[i-1];
            end
        end
    end

    // =====================================================================
    //  Combinational datapath: pre-adds, multiplies, adder trees
    // =====================================================================
    //
    //  y(3m)   = Σ h0(j)[dl_0[j] + dl_1[64-j]]  +  Σ h1(j)[dl_2[1+j] + dl_2[64-j]]
    //  y(3m+1) = Σ h0(j)[dl_1[j] + dl_2[64-j]]  +  Σ h1(j)[dl_0[j]   + dl_0[63-j]]
    //  y(3m+2) = Σ h0(j)[dl_2[j] + dl_0[63-j]]  +  Σ h1(j)[dl_1[j]   + dl_1[63-j]]
    //
    //  H_0 cross pre-adds:  j = 0..63   (64 mults × 3 outputs = 192)
    //  H_1 self-sym folds:  j = 0..31   (32 mults × 3 outputs =  96)
    //  Total: 288 multipliers
    // =====================================================================

    // --- H_0 cross pre-adds (64 per output) ---
    reg signed [W_PREADD-1:0] xpa_y0 [0:SUB_LEN-1];
    reg signed [W_PREADD-1:0] xpa_y1 [0:SUB_LEN-1];
    reg signed [W_PREADD-1:0] xpa_y2 [0:SUB_LEN-1];

    // --- H_1 self-symmetry pre-adds (32 per output) ---
    reg signed [W_PREADD-1:0] spa_y0 [0:HALF_H1-1];
    reg signed [W_PREADD-1:0] spa_y1 [0:HALF_H1-1];
    reg signed [W_PREADD-1:0] spa_y2 [0:HALF_H1-1];

    // --- Products ---
    reg signed [W_MULT-1:0] prod_h0_y0 [0:SUB_LEN-1];
    reg signed [W_MULT-1:0] prod_h0_y1 [0:SUB_LEN-1];
    reg signed [W_MULT-1:0] prod_h0_y2 [0:SUB_LEN-1];
    reg signed [W_MULT-1:0] prod_h1_y0 [0:HALF_H1-1];
    reg signed [W_MULT-1:0] prod_h1_y1 [0:HALF_H1-1];
    reg signed [W_MULT-1:0] prod_h1_y2 [0:HALF_H1-1];

    // --- Pre-add + multiply (combinational) ---
    always @(*) begin
        for (i = 0; i < SUB_LEN; i = i + 1) begin
            // H_0/H_2 cross pre-adds
            xpa_y0[i] = dl_0[i] + dl_1[SUB_LEN - i];      // dl_0[j] + dl_1[64-j]
            xpa_y1[i] = dl_1[i] + dl_2[SUB_LEN - i];      // dl_1[j] + dl_2[64-j]
            xpa_y2[i] = dl_2[i] + dl_0[SUB_LEN - 1 - i];  // dl_2[j] + dl_0[63-j]

            // H_0 products
            prod_h0_y0[i] = xpa_y0[i] * coeff_h0[i];
            prod_h0_y1[i] = xpa_y1[i] * coeff_h0[i];
            prod_h0_y2[i] = xpa_y2[i] * coeff_h0[i];
        end

        for (i = 0; i < HALF_H1; i = i + 1) begin
            // H_1 self-symmetry pre-adds
            spa_y0[i] = dl_2[1 + i] + dl_2[SUB_LEN - i];  // dl_2[1+j] + dl_2[64-j]
            spa_y1[i] = dl_0[i]     + dl_0[SUB_LEN - 1 - i]; // dl_0[j] + dl_0[63-j]
            spa_y2[i] = dl_1[i]     + dl_1[SUB_LEN - 1 - i]; // dl_1[j] + dl_1[63-j]

            // H_1 products
            prod_h1_y0[i] = spa_y0[i] * coeff_h1[i];
            prod_h1_y1[i] = spa_y1[i] * coeff_h1[i];
            prod_h1_y2[i] = spa_y2[i] * coeff_h1[i];
        end
    end

    // --- Combinational binary adder trees ---
    // Merge 64 H0 + 32 H1 = 96 products per output, pad to 128,
    // then 7-level binary tree to prevent DSP chain inference (max 22).

    localparam TOTAL_PROD  = SUB_LEN + HALF_H1;  // 96
    localparam TREE_STAGES = clog2(TOTAL_PROD);   // 7
    localparam N_PAD       = 1 << TREE_STAGES;    // 128

    // y0 tree
    reg signed [W_ACCUM-1:0] y0_t0 [0:N_PAD-1];
    reg signed [W_ACCUM-1:0] y0_t1 [0:(N_PAD/2)-1];
    reg signed [W_ACCUM-1:0] y0_t2 [0:(N_PAD/4)-1];
    reg signed [W_ACCUM-1:0] y0_t3 [0:(N_PAD/8)-1];
    reg signed [W_ACCUM-1:0] y0_t4 [0:(N_PAD/16)-1];
    reg signed [W_ACCUM-1:0] y0_t5 [0:(N_PAD/32)-1];
    reg signed [W_ACCUM-1:0] y0_t6 [0:(N_PAD/64)-1];

    // y1 tree
    reg signed [W_ACCUM-1:0] y1_t0 [0:N_PAD-1];
    reg signed [W_ACCUM-1:0] y1_t1 [0:(N_PAD/2)-1];
    reg signed [W_ACCUM-1:0] y1_t2 [0:(N_PAD/4)-1];
    reg signed [W_ACCUM-1:0] y1_t3 [0:(N_PAD/8)-1];
    reg signed [W_ACCUM-1:0] y1_t4 [0:(N_PAD/16)-1];
    reg signed [W_ACCUM-1:0] y1_t5 [0:(N_PAD/32)-1];
    reg signed [W_ACCUM-1:0] y1_t6 [0:(N_PAD/64)-1];

    // y2 tree
    reg signed [W_ACCUM-1:0] y2_t0 [0:N_PAD-1];
    reg signed [W_ACCUM-1:0] y2_t1 [0:(N_PAD/2)-1];
    reg signed [W_ACCUM-1:0] y2_t2 [0:(N_PAD/4)-1];
    reg signed [W_ACCUM-1:0] y2_t3 [0:(N_PAD/8)-1];
    reg signed [W_ACCUM-1:0] y2_t4 [0:(N_PAD/16)-1];
    reg signed [W_ACCUM-1:0] y2_t5 [0:(N_PAD/32)-1];
    reg signed [W_ACCUM-1:0] y2_t6 [0:(N_PAD/64)-1];

    reg signed [W_ACCUM-1:0] sum_y0, sum_y1, sum_y2;

    always @(*) begin
        // Load H0 products (indices 0..63)
        for (i = 0; i < SUB_LEN; i = i + 1) begin
            y0_t0[i] = prod_h0_y0[i];
            y1_t0[i] = prod_h0_y1[i];
            y2_t0[i] = prod_h0_y2[i];
        end
        // Load H1 products (indices 64..95)
        for (i = 0; i < HALF_H1; i = i + 1) begin
            y0_t0[SUB_LEN + i] = prod_h1_y0[i];
            y1_t0[SUB_LEN + i] = prod_h1_y1[i];
            y2_t0[SUB_LEN + i] = prod_h1_y2[i];
        end
        // Zero-pad (indices 96..127)
        for (i = TOTAL_PROD; i < N_PAD; i = i + 1) begin
            y0_t0[i] = {W_ACCUM{1'b0}};
            y1_t0[i] = {W_ACCUM{1'b0}};
            y2_t0[i] = {W_ACCUM{1'b0}};
        end

        // 7-level pairwise reduction
        for (i = 0; i < N_PAD/2; i = i + 1) begin
            y0_t1[i] = y0_t0[2*i] + y0_t0[2*i+1];
            y1_t1[i] = y1_t0[2*i] + y1_t0[2*i+1];
            y2_t1[i] = y2_t0[2*i] + y2_t0[2*i+1];
        end
        for (i = 0; i < N_PAD/4; i = i + 1) begin
            y0_t2[i] = y0_t1[2*i] + y0_t1[2*i+1];
            y1_t2[i] = y1_t1[2*i] + y1_t1[2*i+1];
            y2_t2[i] = y2_t1[2*i] + y2_t1[2*i+1];
        end
        for (i = 0; i < N_PAD/8; i = i + 1) begin
            y0_t3[i] = y0_t2[2*i] + y0_t2[2*i+1];
            y1_t3[i] = y1_t2[2*i] + y1_t2[2*i+1];
            y2_t3[i] = y2_t2[2*i] + y2_t2[2*i+1];
        end
        for (i = 0; i < N_PAD/16; i = i + 1) begin
            y0_t4[i] = y0_t3[2*i] + y0_t3[2*i+1];
            y1_t4[i] = y1_t3[2*i] + y1_t3[2*i+1];
            y2_t4[i] = y2_t3[2*i] + y2_t3[2*i+1];
        end
        for (i = 0; i < N_PAD/32; i = i + 1) begin
            y0_t5[i] = y0_t4[2*i] + y0_t4[2*i+1];
            y1_t5[i] = y1_t4[2*i] + y1_t4[2*i+1];
            y2_t5[i] = y2_t4[2*i] + y2_t4[2*i+1];
        end
        for (i = 0; i < N_PAD/64; i = i + 1) begin
            y0_t6[i] = y0_t5[2*i] + y0_t5[2*i+1];
            y1_t6[i] = y1_t5[2*i] + y1_t5[2*i+1];
            y2_t6[i] = y2_t5[2*i] + y2_t5[2*i+1];
        end

        sum_y0 = y0_t6[0] + y0_t6[1];
        sum_y1 = y1_t6[0] + y1_t6[1];
        sum_y2 = y2_t6[0] + y2_t6[1];
    end

    // --- Output register ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_0     <= {W_OUT{1'b0}};
            dout_1     <= {W_OUT{1'b0}};
            dout_2     <= {W_OUT{1'b0}};
            dout_valid <= 1'b0;
        end else begin
            dout_0     <= sat_output(sum_y0);
            dout_1     <= sat_output(sum_y1);
            dout_2     <= sat_output(sum_y2);
            dout_valid <= din_valid;
        end
    end

endmodule
