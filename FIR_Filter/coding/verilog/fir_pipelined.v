// ============================================================================
// fir_pipelined.v — Pipelined Adder-Tree FIR Filter (symmetric, linear phase)
// ============================================================================
// Same datapath as fir_basic.v but with PIPELINE REGISTERS at every stage
// of the binary adder tree.  This breaks the critical path from
//   96 products → 1 sum  (combinational in fir_basic)
// into 7 registered stages (ceil(log2(96)) = 7), greatly improving Fmax.
//
// Pipeline latency: 7 extra clock cycles compared to fir_basic.
// Throughput:       1 sample/clock (same), but at a much higher Fmax.
//
// 192-tap, Q20, 21-bit signed coefficients.
// Internal accumulation stays at 38 bits; the output saturates to 32 bits.
// ============================================================================

module fir_pipelined #(
    parameter NUM_TAPS  = 192,
    parameter W_IN      = 16,
    parameter W_COEFF   = 21,
    parameter W_OUT     = 32
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire signed [W_IN-1:0]  din,
    input  wire                    din_valid,
    output reg  signed [W_OUT-1:0] dout,
    output reg                     dout_valid
);

    localparam HALF     = NUM_TAPS / 2;   // 96
    localparam W_PREADD = W_IN + 1;
    localparam W_MULT   = W_PREADD + W_COEFF;
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

    // Number of adder-tree pipeline stages
    localparam STAGES = clog2(HALF);      // 7

    // ----- Coefficient ROM -----
    reg signed [W_COEFF-1:0] coeff [0:HALF-1];

    initial begin  // coefficient ROM
        coeff[ 0] =  21'sd153;      coeff[ 1] =  21'sd317;
        coeff[ 2] =  21'sd540;      coeff[ 3] =  21'sd737;
        coeff[ 4] =  21'sd802;      coeff[ 5] =  21'sd626;
        coeff[ 6] =  21'sd136;      coeff[ 7] = -21'sd660;
        coeff[ 8] = -21'sd1648;     coeff[ 9] = -21'sd2619;
        coeff[10] = -21'sd3315;     coeff[11] = -21'sd3513;
        coeff[12] = -21'sd3102;     coeff[13] = -21'sd2148;
        coeff[14] = -21'sd891;      coeff[15] =  21'sd311;
        coeff[16] =  21'sd1099;     coeff[17] =  21'sd1239;
        coeff[18] =  21'sd718;      coeff[19] = -21'sd240;
        coeff[20] = -21'sd1237;     coeff[21] = -21'sd1850;
        coeff[22] = -21'sd1794;     coeff[23] = -21'sd1043;
        coeff[24] =  21'sd142;      coeff[25] =  21'sd1300;
        coeff[26] =  21'sd1950;     coeff[27] =  21'sd1789;
        coeff[28] =  21'sd833;      coeff[29] = -21'sd565;
        coeff[30] = -21'sd1839;     coeff[31] = -21'sd2431;
        coeff[32] = -21'sd2033;     coeff[33] = -21'sd737;
        coeff[34] =  21'sd973;      coeff[35] =  21'sd2395;
        coeff[36] =  21'sd2896;     coeff[37] =  21'sd2186;
        coeff[38] =  21'sd474;      coeff[39] = -21'sd1581;
        coeff[40] = -21'sd3120;     coeff[41] = -21'sd3435;
        coeff[42] = -21'sd2292;     coeff[43] = -21'sd66;
        coeff[44] =  21'sd2368;     coeff[45] =  21'sd3972;
        coeff[46] =  21'sd3986;     coeff[47] =  21'sd2274;
        coeff[48] = -21'sd562;      coeff[49] = -21'sd3384;
        coeff[50] = -21'sd4965;     coeff[51] = -21'sd4519;
        coeff[52] = -21'sd2073;     coeff[53] =  21'sd1474;
        coeff[54] =  21'sd4672;     coeff[55] =  21'sd6102;
        coeff[56] =  21'sd4993;     coeff[57] =  21'sd1617;
        coeff[58] = -21'sd2748;     coeff[59] = -21'sd6284;
        coeff[60] = -21'sd7380;     coeff[61] = -21'sd5348;
        coeff[62] = -21'sd801;      coeff[63] =  21'sd4497;
        coeff[64] =  21'sd8299;     coeff[65] =  21'sd8810;
        coeff[66] =  21'sd5503;     coeff[67] = -21'sd530;
        coeff[68] = -21'sd6906;     coeff[69] = -21'sd10864;
        coeff[70] = -21'sd10430;    coeff[71] = -21'sd5350;
        coeff[72] =  21'sd2627;     coeff[73] =  21'sd10302;
        coeff[74] =  21'sd14263;    coeff[75] =  21'sd12345;
        coeff[76] =  21'sd4702;     coeff[77] = -21'sd5986;
        coeff[78] = -21'sd15380;    coeff[79] = -21'sd19145;
        coeff[80] = -21'sd14827;    coeff[81] = -21'sd3153;
        coeff[82] =  21'sd11823;    coeff[83] =  21'sd23969;
        coeff[84] =  21'sd27347;    coeff[85] =  21'sd18748;
        coeff[86] = -21'sd493;      coeff[87] = -21'sd24192;
        coeff[88] = -21'sd42822;    coeff[89] = -21'sd46466;
        coeff[90] = -21'sd28292;    coeff[91] =  21'sd12648;
        coeff[92] =  21'sd70338;    coeff[93] =  21'sd132943;
        coeff[94] =  21'sd185938;   coeff[95] =  21'sd216278;
    end

    // ----- Delay line -----
    reg signed [W_IN-1:0] tap [0:NUM_TAPS-1];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < NUM_TAPS; i = i + 1)
                tap[i] <= {W_IN{1'b0}};
        end else if (din_valid) begin
            tap[0] <= din;
            for (i = 1; i < NUM_TAPS; i = i + 1)
                tap[i] <= tap[i-1];
        end
    end

    // ----- Pre-add + multiply (combinational) -----
    reg signed [W_PREADD-1:0] preadd  [0:HALF-1];
    reg signed [W_MULT-1:0]   product [0:HALF-1];

    always @(*) begin
        for (i = 0; i < HALF; i = i + 1) begin
            preadd[i]  = tap[i] + tap[NUM_TAPS-1-i];
            product[i] = preadd[i] * coeff[i];
        end
    end

    // =====================================================================
    //  PIPELINED BINARY ADDER TREE
    // =====================================================================
    //  Stage 0 input:  96 products  (W_MULT wide)
    //  Stage 0 output: 48 partial sums (registered)
    //  Stage 1 output: 24
    //  Stage 2 output: 12
    //  Stage 3 output:  6
    //  Stage 4 output:  3
    //  Stage 5 output:  2  (one pair + one pass-through)
    //  Stage 6 output:  1  → final sum
    //
    //  We pad the input count up to the next power of 2 (128) with zeros
    //  so the tree is perfectly balanced.
    // =====================================================================

    localparam N_PADDED = 1 << STAGES;  // 128

    // Stage 0: register the products (sign-extended to W_ACCUM), padded to 128
    reg signed [W_ACCUM-1:0] tree_s0 [0:N_PADDED-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_PADDED; i = i + 1)
                tree_s0[i] <= {W_ACCUM{1'b0}};
        end else begin
            for (i = 0; i < HALF; i = i + 1)
                tree_s0[i] <= product[i];
            for (i = HALF; i < N_PADDED; i = i + 1)
                tree_s0[i] <= {W_ACCUM{1'b0}};
        end
    end

    // Stages 1..STAGES: each halves the count, registered
    reg signed [W_ACCUM-1:0] tree_s1 [0:(N_PADDED/2)-1];    // 64
    reg signed [W_ACCUM-1:0] tree_s2 [0:(N_PADDED/4)-1];    // 32
    reg signed [W_ACCUM-1:0] tree_s3 [0:(N_PADDED/8)-1];    // 16
    reg signed [W_ACCUM-1:0] tree_s4 [0:(N_PADDED/16)-1];   //  8
    reg signed [W_ACCUM-1:0] tree_s5 [0:(N_PADDED/32)-1];   //  4
    reg signed [W_ACCUM-1:0] tree_s6 [0:(N_PADDED/64)-1];   //  2
    reg signed [W_ACCUM-1:0] tree_s7;                        //  1

    // Stage 1: 128 → 64
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            for (i = 0; i < N_PADDED/2; i = i + 1) tree_s1[i] <= 0;
        else
            for (i = 0; i < N_PADDED/2; i = i + 1)
                tree_s1[i] <= tree_s0[2*i] + tree_s0[2*i+1];
    end

    // Stage 2: 64 → 32
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            for (i = 0; i < N_PADDED/4; i = i + 1) tree_s2[i] <= 0;
        else
            for (i = 0; i < N_PADDED/4; i = i + 1)
                tree_s2[i] <= tree_s1[2*i] + tree_s1[2*i+1];
    end

    // Stage 3: 32 → 16
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            for (i = 0; i < N_PADDED/8; i = i + 1) tree_s3[i] <= 0;
        else
            for (i = 0; i < N_PADDED/8; i = i + 1)
                tree_s3[i] <= tree_s2[2*i] + tree_s2[2*i+1];
    end

    // Stage 4: 16 → 8
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            for (i = 0; i < N_PADDED/16; i = i + 1) tree_s4[i] <= 0;
        else
            for (i = 0; i < N_PADDED/16; i = i + 1)
                tree_s4[i] <= tree_s3[2*i] + tree_s3[2*i+1];
    end

    // Stage 5: 8 → 4
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            for (i = 0; i < N_PADDED/32; i = i + 1) tree_s5[i] <= 0;
        else
            for (i = 0; i < N_PADDED/32; i = i + 1)
                tree_s5[i] <= tree_s4[2*i] + tree_s4[2*i+1];
    end

    // Stage 6: 4 → 2
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            for (i = 0; i < N_PADDED/64; i = i + 1) tree_s6[i] <= 0;
        else
            for (i = 0; i < N_PADDED/64; i = i + 1)
                tree_s6[i] <= tree_s5[2*i] + tree_s5[2*i+1];
    end

    // Stage 7: 2 → 1
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tree_s7 <= 0;
        else
            tree_s7 <= tree_s6[0] + tree_s6[1];
    end

    // ----- Valid pipeline (shift register matching tree depth) -----
    // Total pipeline: 1 (product reg) + 7 (tree stages) = 8 cycles
    reg [STAGES:0] valid_pipe;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_pipe <= 0;
        else
            valid_pipe <= {valid_pipe[STAGES-1:0], din_valid};
    end

    // ----- Output -----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout       <= 0;
            dout_valid <= 1'b0;
        end else begin
            dout       <= sat_output(tree_s7);
            dout_valid <= valid_pipe[STAGES];
        end
    end

endmodule
