// ============================================================================
// fir_parallel_L2.v — L=2 Polyphase Parallel FIR Filter
// ============================================================================
// Processes TWO input samples per clock and produces TWO output samples per
// clock, doubling throughput compared to fir_basic.
//
// Polyphase decomposition of H(z) = H_e(z^2) + z^{-1} H_o(z^2):
//   H_e: even-indexed coefficients  h(0), h(2), ..., h(190)  (96 taps)
//   H_o: odd-indexed coefficients   h(1), h(3), ..., h(191)  (96 taps)
//
// Because h(k) = h(191-k) (linear-phase symmetry), h_e(j) = h_o(95-j).
// This lets us use CROSS PRE-ADDS to compute both outputs with only 96
// multiplies per output (192 total) instead of 4 × 96 = 384 naively:
//
//   y_0(k) = y(2k)   = Σ h_e(j) · [dl_0(j) + dl_1(96-j)]
//   y_1(k) = y(2k+1) = Σ h_e(j) · [dl_1(j) + dl_0(95-j)]
//
// 192-tap, Q20, 21-bit signed coefficients.
// Internal accumulation stays at 38 bits; the outputs saturate to 32 bits.
// ============================================================================

module fir_parallel_L2 #(
    parameter NUM_TAPS  = 192,
    parameter W_IN      = 16,
    parameter W_COEFF   = 21,
    parameter W_OUT     = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire signed [W_IN-1:0]  din_0,       // even sample  x(2k)
    input  wire signed [W_IN-1:0]  din_1,       // odd  sample  x(2k+1)
    input  wire                    din_valid,
    output reg  signed [W_OUT-1:0] dout_0,      // even output  y(2k)
    output reg  signed [W_OUT-1:0] dout_1,      // odd  output  y(2k+1)
    output reg                     dout_valid
);

    // Each polyphase sub-filter length
    localparam HALF_TAPS = NUM_TAPS / 2;    // 96

    localparam W_PREADD = W_IN + 1;         // 17 bits  (sum of two inputs)
    localparam W_MULT   = W_PREADD + W_COEFF; // 38 bits
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

    // ----- Even polyphase coefficient ROM: h_e(j) = h(2j) -----
    // For j = 0..47:  h(2j) = original coeff[2j]
    // For j = 48..95: h(2j) = original coeff[191 - 2j]
    reg signed [W_COEFF-1:0] coeff_e [0:HALF_TAPS-1];

    initial begin
        coeff_e[ 0] =  21'sd153;      coeff_e[ 1] =  21'sd540;
        coeff_e[ 2] =  21'sd802;      coeff_e[ 3] =  21'sd136;
        coeff_e[ 4] = -21'sd1648;     coeff_e[ 5] = -21'sd3315;
        coeff_e[ 6] = -21'sd3102;     coeff_e[ 7] = -21'sd891;
        coeff_e[ 8] =  21'sd1099;     coeff_e[ 9] =  21'sd718;
        coeff_e[10] = -21'sd1237;     coeff_e[11] = -21'sd1794;
        coeff_e[12] =  21'sd142;      coeff_e[13] =  21'sd1950;
        coeff_e[14] =  21'sd833;      coeff_e[15] = -21'sd1839;
        coeff_e[16] = -21'sd2033;     coeff_e[17] =  21'sd973;
        coeff_e[18] =  21'sd2896;     coeff_e[19] =  21'sd474;
        coeff_e[20] = -21'sd3120;     coeff_e[21] = -21'sd2292;
        coeff_e[22] =  21'sd2368;     coeff_e[23] =  21'sd3986;
        coeff_e[24] = -21'sd562;      coeff_e[25] = -21'sd4965;
        coeff_e[26] = -21'sd2073;     coeff_e[27] =  21'sd4672;
        coeff_e[28] =  21'sd4993;     coeff_e[29] = -21'sd2748;
        coeff_e[30] = -21'sd7380;     coeff_e[31] = -21'sd801;
        coeff_e[32] =  21'sd8299;     coeff_e[33] =  21'sd5503;
        coeff_e[34] = -21'sd6906;     coeff_e[35] = -21'sd10430;
        coeff_e[36] =  21'sd2627;     coeff_e[37] =  21'sd14263;
        coeff_e[38] =  21'sd4702;     coeff_e[39] = -21'sd15380;
        coeff_e[40] = -21'sd14827;    coeff_e[41] =  21'sd11823;
        coeff_e[42] =  21'sd27347;    coeff_e[43] = -21'sd493;
        coeff_e[44] = -21'sd42822;    coeff_e[45] = -21'sd28292;
        coeff_e[46] =  21'sd70338;    coeff_e[47] =  21'sd185938;
        coeff_e[48] =  21'sd216278;   coeff_e[49] =  21'sd132943;
        coeff_e[50] =  21'sd12648;    coeff_e[51] = -21'sd46466;
        coeff_e[52] = -21'sd24192;    coeff_e[53] =  21'sd18748;
        coeff_e[54] =  21'sd23969;    coeff_e[55] = -21'sd3153;
        coeff_e[56] = -21'sd19145;    coeff_e[57] = -21'sd5986;
        coeff_e[58] =  21'sd12345;    coeff_e[59] =  21'sd10302;
        coeff_e[60] = -21'sd5350;     coeff_e[61] = -21'sd10864;
        coeff_e[62] = -21'sd530;      coeff_e[63] =  21'sd8810;
        coeff_e[64] =  21'sd4497;     coeff_e[65] = -21'sd5348;
        coeff_e[66] = -21'sd6284;     coeff_e[67] =  21'sd1617;
        coeff_e[68] =  21'sd6102;     coeff_e[69] =  21'sd1474;
        coeff_e[70] = -21'sd4519;     coeff_e[71] = -21'sd3384;
        coeff_e[72] =  21'sd2274;     coeff_e[73] =  21'sd3972;
        coeff_e[74] = -21'sd66;       coeff_e[75] = -21'sd3435;
        coeff_e[76] = -21'sd1581;     coeff_e[77] =  21'sd2186;
        coeff_e[78] =  21'sd2395;     coeff_e[79] = -21'sd737;
        coeff_e[80] = -21'sd2431;     coeff_e[81] = -21'sd565;
        coeff_e[82] =  21'sd1789;     coeff_e[83] =  21'sd1300;
        coeff_e[84] = -21'sd1043;     coeff_e[85] = -21'sd1850;
        coeff_e[86] = -21'sd240;      coeff_e[87] =  21'sd1239;
        coeff_e[88] =  21'sd311;      coeff_e[89] = -21'sd2148;
        coeff_e[90] = -21'sd3513;     coeff_e[91] = -21'sd2619;
        coeff_e[92] = -21'sd660;      coeff_e[93] =  21'sd626;
        coeff_e[94] =  21'sd737;      coeff_e[95] =  21'sd317;
    end

    // ----- Delay lines -----
    // dl_0: 96 elements for even-sample stream
    // dl_1: 97 elements for odd-sample stream (one extra for y_0 cross term)
    reg signed [W_IN-1:0] dl_0 [0:HALF_TAPS-1];
    reg signed [W_IN-1:0] dl_1 [0:HALF_TAPS];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < HALF_TAPS; i = i + 1)
                dl_0[i] <= {W_IN{1'b0}};
            for (i = 0; i <= HALF_TAPS; i = i + 1)
                dl_1[i] <= {W_IN{1'b0}};
        end else if (din_valid) begin
            dl_0[0] <= din_0;
            for (i = 1; i < HALF_TAPS; i = i + 1)
                dl_0[i] <= dl_0[i-1];
            dl_1[0] <= din_1;
            for (i = 1; i <= HALF_TAPS; i = i + 1)
                dl_1[i] <= dl_1[i-1];
        end
    end

    // ----- Cross pre-add + multiply (combinational) -----
    // y_0: pa_y0[j] = dl_0[j]     + dl_1[96-j]    (uses dl_1 indices 1..96)
    // y_1: pa_y1[j] = dl_1[j]     + dl_0[95-j]
    reg signed [W_PREADD-1:0] pa_y0 [0:HALF_TAPS-1];
    reg signed [W_PREADD-1:0] pa_y1 [0:HALF_TAPS-1];
    reg signed [W_MULT-1:0]   prod_y0 [0:HALF_TAPS-1];
    reg signed [W_MULT-1:0]   prod_y1 [0:HALF_TAPS-1];

    always @(*) begin
        for (i = 0; i < HALF_TAPS; i = i + 1) begin
            pa_y0[i]   = dl_0[i] + dl_1[HALF_TAPS - i];
            pa_y1[i]   = dl_1[i] + dl_0[HALF_TAPS - 1 - i];
            prod_y0[i] = pa_y0[i] * coeff_e[i];
            prod_y1[i] = pa_y1[i] * coeff_e[i];
        end
    end

    // ----- Combinational binary adder trees -----
    // Structured as trees to prevent Quartus DSP chain inference (max 22).
    // 96 products → pad to 128 → 7-level tree → 1 final sum, per output.

    localparam TREE_STAGES = clog2(HALF_TAPS);  // 7
    localparam N_PAD       = 1 << TREE_STAGES;  // 128

    // y0 tree
    reg signed [W_ACCUM-1:0] y0_t0 [0:N_PAD-1];
    reg signed [W_ACCUM-1:0] y0_t1 [0:(N_PAD/2)-1];
    reg signed [W_ACCUM-1:0] y0_t2 [0:(N_PAD/4)-1];
    reg signed [W_ACCUM-1:0] y0_t3 [0:(N_PAD/8)-1];
    reg signed [W_ACCUM-1:0] y0_t4 [0:(N_PAD/16)-1];
    reg signed [W_ACCUM-1:0] y0_t5 [0:(N_PAD/32)-1];
    reg signed [W_ACCUM-1:0] y0_t6 [0:(N_PAD/64)-1];
    reg signed [W_ACCUM-1:0] sum_y0;

    // y1 tree
    reg signed [W_ACCUM-1:0] y1_t0 [0:N_PAD-1];
    reg signed [W_ACCUM-1:0] y1_t1 [0:(N_PAD/2)-1];
    reg signed [W_ACCUM-1:0] y1_t2 [0:(N_PAD/4)-1];
    reg signed [W_ACCUM-1:0] y1_t3 [0:(N_PAD/8)-1];
    reg signed [W_ACCUM-1:0] y1_t4 [0:(N_PAD/16)-1];
    reg signed [W_ACCUM-1:0] y1_t5 [0:(N_PAD/32)-1];
    reg signed [W_ACCUM-1:0] y1_t6 [0:(N_PAD/64)-1];
    reg signed [W_ACCUM-1:0] sum_y1;

    always @(*) begin
        // Load products, zero-pad
        for (i = 0; i < HALF_TAPS; i = i + 1) begin
            y0_t0[i] = prod_y0[i];
            y1_t0[i] = prod_y1[i];
        end
        for (i = HALF_TAPS; i < N_PAD; i = i + 1) begin
            y0_t0[i] = {W_ACCUM{1'b0}};
            y1_t0[i] = {W_ACCUM{1'b0}};
        end

        // 7-level pairwise reduction
        for (i = 0; i < N_PAD/2; i = i + 1) begin
            y0_t1[i] = y0_t0[2*i] + y0_t0[2*i+1];
            y1_t1[i] = y1_t0[2*i] + y1_t0[2*i+1];
        end
        for (i = 0; i < N_PAD/4; i = i + 1) begin
            y0_t2[i] = y0_t1[2*i] + y0_t1[2*i+1];
            y1_t2[i] = y1_t1[2*i] + y1_t1[2*i+1];
        end
        for (i = 0; i < N_PAD/8; i = i + 1) begin
            y0_t3[i] = y0_t2[2*i] + y0_t2[2*i+1];
            y1_t3[i] = y1_t2[2*i] + y1_t2[2*i+1];
        end
        for (i = 0; i < N_PAD/16; i = i + 1) begin
            y0_t4[i] = y0_t3[2*i] + y0_t3[2*i+1];
            y1_t4[i] = y1_t3[2*i] + y1_t3[2*i+1];
        end
        for (i = 0; i < N_PAD/32; i = i + 1) begin
            y0_t5[i] = y0_t4[2*i] + y0_t4[2*i+1];
            y1_t5[i] = y1_t4[2*i] + y1_t4[2*i+1];
        end
        for (i = 0; i < N_PAD/64; i = i + 1) begin
            y0_t6[i] = y0_t5[2*i] + y0_t5[2*i+1];
            y1_t6[i] = y1_t5[2*i] + y1_t5[2*i+1];
        end

        sum_y0 = y0_t6[0] + y0_t6[1];
        sum_y1 = y1_t6[0] + y1_t6[1];
    end

    // ----- Output register -----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_0     <= {W_OUT{1'b0}};
            dout_1     <= {W_OUT{1'b0}};
            dout_valid <= 1'b0;
        end else begin
            dout_0     <= sat_output(sum_y0);
            dout_1     <= sat_output(sum_y1);
            dout_valid <= din_valid;
        end
    end

endmodule
