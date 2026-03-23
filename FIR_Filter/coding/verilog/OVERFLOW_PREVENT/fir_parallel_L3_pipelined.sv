// ============================================================================
// fir_parallel_L3_pipelined.sv — L=3 Polyphase Parallel FIR with Pipelined
//                                 Adder Trees
// ============================================================================
// Same datapath as fir_parallel_L3.sv but with PIPELINE REGISTERS at every
// stage of each output channel's binary adder tree.  This breaks the critical
// path from  96 products → 1 sum  (combinational in fir_parallel_L3)
// into 7 registered stages (ceil(log2(96)) = 7), greatly improving Fmax.
//
// Pipeline latency: 8 extra clock cycles compared to fir_parallel_L3.
//   - 1 cycle:  product register (tree stage 0)
//   - 7 cycles: binary adder tree (stages 1–7)
// Throughput: 3 samples/clock (same), but at a much higher Fmax.
//
// Multiplier count unchanged: 288 (192 H_0 + 96 H_1).
// 192-tap, Q20, 21-bit signed coefficients, 38-bit accumulator.
// ============================================================================

module fir_parallel_L3_pipelined #(
    parameter NUM_TAPS  = 192,
    parameter W_IN      = 16,
    parameter W_COEFF   = 21,
    parameter W_OUT     = 38
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
    localparam W_MULT   = W_PREADD + W_COEFF; // 38

    // Number of products per output channel: 64 (H0) + 32 (H1) = 96
    localparam N_PRODS  = SUB_LEN + HALF_H1; // 96
    localparam STAGES   = $clog2(N_PRODS);    // 7
    localparam N_PADDED = 1 << STAGES;        // 128

    // =====================================================================
    //  Coefficient ROMs  (identical to fir_parallel_L3)
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
    //  Delay lines  (identical to fir_parallel_L3)
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
    //  Combinational pre-adds and multiplies  (identical to fir_parallel_L3)
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

    always @(*) begin
        for (i = 0; i < SUB_LEN; i = i + 1) begin
            // H_0/H_2 cross pre-adds
            xpa_y0[i] = dl_0[i] + dl_1[SUB_LEN - i];
            xpa_y1[i] = dl_1[i] + dl_2[SUB_LEN - i];
            xpa_y2[i] = dl_2[i] + dl_0[SUB_LEN - 1 - i];

            // H_0 products
            prod_h0_y0[i] = xpa_y0[i] * coeff_h0[i];
            prod_h0_y1[i] = xpa_y1[i] * coeff_h0[i];
            prod_h0_y2[i] = xpa_y2[i] * coeff_h0[i];
        end

        for (i = 0; i < HALF_H1; i = i + 1) begin
            // H_1 self-symmetry pre-adds
            spa_y0[i] = dl_2[1 + i] + dl_2[SUB_LEN - i];
            spa_y1[i] = dl_0[i]     + dl_0[SUB_LEN - 1 - i];
            spa_y2[i] = dl_1[i]     + dl_1[SUB_LEN - 1 - i];

            // H_1 products
            prod_h1_y0[i] = spa_y0[i] * coeff_h1[i];
            prod_h1_y1[i] = spa_y1[i] * coeff_h1[i];
            prod_h1_y2[i] = spa_y2[i] * coeff_h1[i];
        end
    end

    // =====================================================================
    //  PIPELINED BINARY ADDER TREES  (one per output channel)
    // =====================================================================
    //  Each channel has 96 products (64 H_0 + 32 H_1), padded to 128.
    //  7 registered stages (ceil(log2(128)) = 7).
    //
    //  Stage 0: register products into 128-entry arrays
    //  Stage 1: 128 → 64
    //  Stage 2:  64 → 32
    //  Stage 3:  32 → 16
    //  Stage 4:  16 →  8
    //  Stage 5:   8 →  4
    //  Stage 6:   4 →  2
    //  Stage 7:   2 →  1  (final sum per channel)
    // =====================================================================

    // --- Stage 0: register products, padded to 128 ---
    reg signed [W_OUT-1:0] s0_y0 [0:N_PADDED-1];
    reg signed [W_OUT-1:0] s0_y1 [0:N_PADDED-1];
    reg signed [W_OUT-1:0] s0_y2 [0:N_PADDED-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_PADDED; i = i + 1) begin
                s0_y0[i] <= {W_OUT{1'b0}};
                s0_y1[i] <= {W_OUT{1'b0}};
                s0_y2[i] <= {W_OUT{1'b0}};
            end
        end else begin
            // H_0 products (indices 0..63)
            for (i = 0; i < SUB_LEN; i = i + 1) begin
                s0_y0[i] <= prod_h0_y0[i];
                s0_y1[i] <= prod_h0_y1[i];
                s0_y2[i] <= prod_h0_y2[i];
            end
            // H_1 products (indices 64..95)
            for (i = 0; i < HALF_H1; i = i + 1) begin
                s0_y0[SUB_LEN + i] <= prod_h1_y0[i];
                s0_y1[SUB_LEN + i] <= prod_h1_y1[i];
                s0_y2[SUB_LEN + i] <= prod_h1_y2[i];
            end
            // Zero padding (indices 96..127)
            for (i = N_PRODS; i < N_PADDED; i = i + 1) begin
                s0_y0[i] <= {W_OUT{1'b0}};
                s0_y1[i] <= {W_OUT{1'b0}};
                s0_y2[i] <= {W_OUT{1'b0}};
            end
        end
    end

    // --- Stage 1: 128 → 64 ---
    reg signed [W_OUT-1:0] s1_y0 [0:(N_PADDED/2)-1];
    reg signed [W_OUT-1:0] s1_y1 [0:(N_PADDED/2)-1];
    reg signed [W_OUT-1:0] s1_y2 [0:(N_PADDED/2)-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_PADDED/2; i = i + 1) begin
                s1_y0[i] <= {W_OUT{1'b0}};
                s1_y1[i] <= {W_OUT{1'b0}};
                s1_y2[i] <= {W_OUT{1'b0}};
            end
        end else begin
            for (i = 0; i < N_PADDED/2; i = i + 1) begin
                s1_y0[i] <= s0_y0[2*i] + s0_y0[2*i+1];
                s1_y1[i] <= s0_y1[2*i] + s0_y1[2*i+1];
                s1_y2[i] <= s0_y2[2*i] + s0_y2[2*i+1];
            end
        end
    end

    // --- Stage 2: 64 → 32 ---
    reg signed [W_OUT-1:0] s2_y0 [0:(N_PADDED/4)-1];
    reg signed [W_OUT-1:0] s2_y1 [0:(N_PADDED/4)-1];
    reg signed [W_OUT-1:0] s2_y2 [0:(N_PADDED/4)-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_PADDED/4; i = i + 1) begin
                s2_y0[i] <= {W_OUT{1'b0}};
                s2_y1[i] <= {W_OUT{1'b0}};
                s2_y2[i] <= {W_OUT{1'b0}};
            end
        end else begin
            for (i = 0; i < N_PADDED/4; i = i + 1) begin
                s2_y0[i] <= s1_y0[2*i] + s1_y0[2*i+1];
                s2_y1[i] <= s1_y1[2*i] + s1_y1[2*i+1];
                s2_y2[i] <= s1_y2[2*i] + s1_y2[2*i+1];
            end
        end
    end

    // --- Stage 3: 32 → 16 ---
    reg signed [W_OUT-1:0] s3_y0 [0:(N_PADDED/8)-1];
    reg signed [W_OUT-1:0] s3_y1 [0:(N_PADDED/8)-1];
    reg signed [W_OUT-1:0] s3_y2 [0:(N_PADDED/8)-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_PADDED/8; i = i + 1) begin
                s3_y0[i] <= {W_OUT{1'b0}};
                s3_y1[i] <= {W_OUT{1'b0}};
                s3_y2[i] <= {W_OUT{1'b0}};
            end
        end else begin
            for (i = 0; i < N_PADDED/8; i = i + 1) begin
                s3_y0[i] <= s2_y0[2*i] + s2_y0[2*i+1];
                s3_y1[i] <= s2_y1[2*i] + s2_y1[2*i+1];
                s3_y2[i] <= s2_y2[2*i] + s2_y2[2*i+1];
            end
        end
    end

    // --- Stage 4: 16 → 8 ---
    reg signed [W_OUT-1:0] s4_y0 [0:(N_PADDED/16)-1];
    reg signed [W_OUT-1:0] s4_y1 [0:(N_PADDED/16)-1];
    reg signed [W_OUT-1:0] s4_y2 [0:(N_PADDED/16)-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_PADDED/16; i = i + 1) begin
                s4_y0[i] <= {W_OUT{1'b0}};
                s4_y1[i] <= {W_OUT{1'b0}};
                s4_y2[i] <= {W_OUT{1'b0}};
            end
        end else begin
            for (i = 0; i < N_PADDED/16; i = i + 1) begin
                s4_y0[i] <= s3_y0[2*i] + s3_y0[2*i+1];
                s4_y1[i] <= s3_y1[2*i] + s3_y1[2*i+1];
                s4_y2[i] <= s3_y2[2*i] + s3_y2[2*i+1];
            end
        end
    end

    // --- Stage 5: 8 → 4 ---
    reg signed [W_OUT-1:0] s5_y0 [0:(N_PADDED/32)-1];
    reg signed [W_OUT-1:0] s5_y1 [0:(N_PADDED/32)-1];
    reg signed [W_OUT-1:0] s5_y2 [0:(N_PADDED/32)-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_PADDED/32; i = i + 1) begin
                s5_y0[i] <= {W_OUT{1'b0}};
                s5_y1[i] <= {W_OUT{1'b0}};
                s5_y2[i] <= {W_OUT{1'b0}};
            end
        end else begin
            for (i = 0; i < N_PADDED/32; i = i + 1) begin
                s5_y0[i] <= s4_y0[2*i] + s4_y0[2*i+1];
                s5_y1[i] <= s4_y1[2*i] + s4_y1[2*i+1];
                s5_y2[i] <= s4_y2[2*i] + s4_y2[2*i+1];
            end
        end
    end

    // --- Stage 6: 4 → 2 ---
    reg signed [W_OUT-1:0] s6_y0 [0:(N_PADDED/64)-1];
    reg signed [W_OUT-1:0] s6_y1 [0:(N_PADDED/64)-1];
    reg signed [W_OUT-1:0] s6_y2 [0:(N_PADDED/64)-1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < N_PADDED/64; i = i + 1) begin
                s6_y0[i] <= {W_OUT{1'b0}};
                s6_y1[i] <= {W_OUT{1'b0}};
                s6_y2[i] <= {W_OUT{1'b0}};
            end
        end else begin
            for (i = 0; i < N_PADDED/64; i = i + 1) begin
                s6_y0[i] <= s5_y0[2*i] + s5_y0[2*i+1];
                s6_y1[i] <= s5_y1[2*i] + s5_y1[2*i+1];
                s6_y2[i] <= s5_y2[2*i] + s5_y2[2*i+1];
            end
        end
    end

    // --- Stage 7: 2 → 1 (final sum per channel) ---
    reg signed [W_OUT-1:0] s7_y0;
    reg signed [W_OUT-1:0] s7_y1;
    reg signed [W_OUT-1:0] s7_y2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s7_y0 <= {W_OUT{1'b0}};
            s7_y1 <= {W_OUT{1'b0}};
            s7_y2 <= {W_OUT{1'b0}};
        end else begin
            s7_y0 <= s6_y0[0] + s6_y0[1];
            s7_y1 <= s6_y1[0] + s6_y1[1];
            s7_y2 <= s6_y2[0] + s6_y2[1];
        end
    end

    // =====================================================================
    //  Valid pipeline (shift register matching tree depth)
    // =====================================================================
    //  Total pipeline: 1 (product reg s0) + 7 (tree stages s1–s7) = 8 cycles
    reg [STAGES:0] valid_pipe;  // 8 bits

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_pipe <= {(STAGES+1){1'b0}};
        else
            valid_pipe <= {valid_pipe[STAGES-1:0], din_valid};
    end

    // =====================================================================
    //  Output register
    // =====================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout_0     <= {W_OUT{1'b0}};
            dout_1     <= {W_OUT{1'b0}};
            dout_2     <= {W_OUT{1'b0}};
            dout_valid <= 1'b0;
        end else begin
            dout_0     <= s7_y0;
            dout_1     <= s7_y1;
            dout_2     <= s7_y2;
            dout_valid <= valid_pipe[STAGES];
        end
    end

endmodule
