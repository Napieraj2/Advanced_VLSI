// ============================================================================
// fir_mcm.sv — Direct-Form FIR Filter with MCM (Multiple Constant Multiply)
//              OVERFLOW CONTROL variant: true 32-bit internal tree
// ============================================================================
// Identical architecture to fir_basic (symmetric pre-adds, binary adder tree)
// but replaces all 96 DSP multipliers with CSD shift-add networks.
//
// CSD decomposition: 453 non-zero digits, 357 shift-add operations, 0 DSPs.
// Internal tree: 32-bit (two’s complement wrap-around, no saturation).
//
// 192-tap, Q20, 21-bit signed coefficients.
// ============================================================================

module fir_mcm #(
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

    localparam HALF = NUM_TAPS / 2;
    localparam W_PREADD = W_IN + 1;

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

    // ----- Pre-add symmetric pairs -----
    reg signed [W_PREADD-1:0] preadd [0:HALF-1];

    always @(*) begin
        for (i = 0; i < HALF; i = i + 1)
            preadd[i] = tap[i] + tap[NUM_TAPS-1-i];
    end

    // ----- Sign-extend pre-adds to W_OUT width for shift-add -----
    wire signed [W_OUT-1:0] pa [0:HALF-1];
    genvar g;
    generate
        for (g = 0; g < HALF; g = g + 1) begin : gen_pa
            assign pa[g] = {{(W_OUT-W_PREADD){preadd[g][W_PREADD-1]}}, preadd[g]};
        end
    endgenerate

    // ----- CSD shift-add products (0 DSP blocks) -----
    reg signed [W_OUT-1:0] product [0:HALF-1];

    always @(*) begin
        product[ 0] =  pa[ 0]          - (pa[ 0] <<< 3) + (pa[ 0] <<< 5) + (pa[ 0] <<< 7);
        product[ 1] =  pa[ 1]          - (pa[ 1] <<< 2) + (pa[ 1] <<< 6) + (pa[ 1] <<< 8);
        product[ 2] =                  - (pa[ 2] <<< 2) + (pa[ 2] <<< 5) + (pa[ 2] <<< 9);
        product[ 3] =  pa[ 3]          - (pa[ 3] <<< 5) - (pa[ 3] <<< 8) + (pa[ 3] <<< 10);
        product[ 4] = (pa[ 4] <<< 1)  + (pa[ 4] <<< 5) - (pa[ 4] <<< 8) + (pa[ 4] <<< 10);
        product[ 5] = (pa[ 5] <<< 1)  - (pa[ 5] <<< 4) + (pa[ 5] <<< 7) + (pa[ 5] <<< 9);
        product[ 6] = (pa[ 6] <<< 3)  + (pa[ 6] <<< 7);
        product[ 7] =                  - (pa[ 7] <<< 2) - (pa[ 7] <<< 4) - (pa[ 7] <<< 7) - (pa[ 7] <<< 9);
        product[ 8] = (pa[ 8] <<< 4)  - (pa[ 8] <<< 7) + (pa[ 8] <<< 9) - (pa[ 8] <<< 11);
        product[ 9] =  pa[ 9]          + (pa[ 9] <<< 2) - (pa[ 9] <<< 6) - (pa[ 9] <<< 9) - (pa[ 9] <<< 11);
        product[10] =  pa[10]          - (pa[10] <<< 2) + (pa[10] <<< 4) - (pa[10] <<< 8) + (pa[10] <<< 10) - (pa[10] <<< 12);
        product[11] = -pa[11]          + (pa[11] <<< 3) + (pa[11] <<< 6) + (pa[11] <<< 9) - (pa[11] <<< 12);
        product[12] = (pa[12] <<< 1)  - (pa[12] <<< 5) + (pa[12] <<< 10) - (pa[12] <<< 12);
        product[13] =                  - (pa[13] <<< 2) + (pa[13] <<< 5) - (pa[13] <<< 7) - (pa[13] <<< 11);
        product[14] =  pa[14]          + (pa[14] <<< 2) + (pa[14] <<< 7) - (pa[14] <<< 10);
        product[15] = -pa[15]          - (pa[15] <<< 3) + (pa[15] <<< 6) + (pa[15] <<< 8);
        product[16] = -pa[16]          - (pa[16] <<< 2) + (pa[16] <<< 4) + (pa[16] <<< 6) + (pa[16] <<< 10);
        product[17] = -pa[17]          - (pa[17] <<< 3) - (pa[17] <<< 5) + (pa[17] <<< 8) + (pa[17] <<< 10);
        product[18] =                  - (pa[18] <<< 1) + (pa[18] <<< 4) - (pa[18] <<< 6) - (pa[18] <<< 8) + (pa[18] <<< 10);
        product[19] = (pa[19] <<< 4)  - (pa[19] <<< 8);
        product[20] = -pa[20]          - (pa[20] <<< 2) - (pa[20] <<< 4) + (pa[20] <<< 6) - (pa[20] <<< 8) - (pa[20] <<< 10);
        product[21] =                  - (pa[21] <<< 1) + (pa[21] <<< 3) - (pa[21] <<< 6) + (pa[21] <<< 8) - (pa[21] <<< 11);
        product[22] =                  - (pa[22] <<< 1) + (pa[22] <<< 8) - (pa[22] <<< 11);
        product[23] =  pa[23]          - (pa[23] <<< 2) - (pa[23] <<< 4) - (pa[23] <<< 10);
        product[24] =                  - (pa[24] <<< 1) + (pa[24] <<< 4) + (pa[24] <<< 7);
        product[25] = (pa[25] <<< 2)  + (pa[25] <<< 4) + (pa[25] <<< 8) + (pa[25] <<< 10);
        product[26] =                  - (pa[26] <<< 1) + (pa[26] <<< 5) - (pa[26] <<< 7) + (pa[26] <<< 11);
        product[27] =  pa[27]          - (pa[27] <<< 2) - (pa[27] <<< 8) + (pa[27] <<< 11);
        product[28] =  pa[28]          + (pa[28] <<< 6) - (pa[28] <<< 8) + (pa[28] <<< 10);
        product[29] = -pa[29]          - (pa[29] <<< 2) + (pa[29] <<< 4) - (pa[29] <<< 6) - (pa[29] <<< 9);
        product[30] =  pa[30]          + (pa[30] <<< 4) - (pa[30] <<< 6) + (pa[30] <<< 8) - (pa[30] <<< 11);
        product[31] =  pa[31]          + (pa[31] <<< 7) - (pa[31] <<< 9) - (pa[31] <<< 11);
        product[32] = -pa[32]          + (pa[32] <<< 4) - (pa[32] <<< 11);
        product[33] = -pa[33]          + (pa[33] <<< 5) + (pa[33] <<< 8) - (pa[33] <<< 10);
        product[34] =  pa[34]          - (pa[34] <<< 2) + (pa[34] <<< 4) - (pa[34] <<< 6) + (pa[34] <<< 10);
        product[35] = -pa[35]          - (pa[35] <<< 2) - (pa[35] <<< 5) - (pa[35] <<< 7) + (pa[35] <<< 9) + (pa[35] <<< 11);
        product[36] = (pa[36] <<< 4)  + (pa[36] <<< 6) - (pa[36] <<< 8) - (pa[36] <<< 10) + (pa[36] <<< 12);
        product[37] = (pa[37] <<< 1)  + (pa[37] <<< 3) + (pa[37] <<< 7) + (pa[37] <<< 11);
        product[38] = (pa[38] <<< 1)  - (pa[38] <<< 3) - (pa[38] <<< 5) + (pa[38] <<< 9);
        product[39] = -pa[39]          + (pa[39] <<< 2) + (pa[39] <<< 4) - (pa[39] <<< 6) + (pa[39] <<< 9) - (pa[39] <<< 11);
        product[40] = (pa[40] <<< 4)  - (pa[40] <<< 6) + (pa[40] <<< 10) - (pa[40] <<< 12);
        product[41] =  pa[41]          + (pa[41] <<< 2) + (pa[41] <<< 4) + (pa[41] <<< 7) + (pa[41] <<< 9) - (pa[41] <<< 12);
        product[42] =                  - (pa[42] <<< 2) + (pa[42] <<< 4) - (pa[42] <<< 8) - (pa[42] <<< 11);
        product[43] =                  - (pa[43] <<< 1) - (pa[43] <<< 6);
        product[44] = (pa[44] <<< 6)  + (pa[44] <<< 8) + (pa[44] <<< 11);
        product[45] = (pa[45] <<< 2)  - (pa[45] <<< 7) + (pa[45] <<< 12);
        product[46] = (pa[46] <<< 1)  + (pa[46] <<< 4) - (pa[46] <<< 7) + (pa[46] <<< 12);
        product[47] = (pa[47] <<< 1)  - (pa[47] <<< 5) + (pa[47] <<< 8) + (pa[47] <<< 11);
        product[48] =                  - (pa[48] <<< 1) + (pa[48] <<< 4) - (pa[48] <<< 6) - (pa[48] <<< 9);
        product[49] = (pa[49] <<< 3)  - (pa[49] <<< 6) - (pa[49] <<< 8) + (pa[49] <<< 10) - (pa[49] <<< 12);
        product[50] = -pa[50]          - (pa[50] <<< 2) + (pa[50] <<< 5) + (pa[50] <<< 7) - (pa[50] <<< 10) - (pa[50] <<< 12);
        product[51] =  pa[51]          - (pa[51] <<< 3) - (pa[51] <<< 5) + (pa[51] <<< 7) - (pa[51] <<< 9) - (pa[51] <<< 12);
        product[52] = -pa[52]          + (pa[52] <<< 3) - (pa[52] <<< 5) - (pa[52] <<< 11);
        product[53] = (pa[53] <<< 1)  - (pa[53] <<< 6) - (pa[53] <<< 9) + (pa[53] <<< 11);
        product[54] = (pa[54] <<< 6)  + (pa[54] <<< 9) + (pa[54] <<< 12);
        product[55] =                  - (pa[55] <<< 1) - (pa[55] <<< 3) - (pa[55] <<< 5) - (pa[55] <<< 11) + (pa[55] <<< 13);
        product[56] =  pa[56]          - (pa[56] <<< 7) + (pa[56] <<< 10) + (pa[56] <<< 12);
        product[57] =  pa[57]          + (pa[57] <<< 4) + (pa[57] <<< 6) - (pa[57] <<< 9) + (pa[57] <<< 11);
        product[58] = (pa[58] <<< 2)  + (pa[58] <<< 6) + (pa[58] <<< 8) + (pa[58] <<< 10) - (pa[58] <<< 12);
        product[59] = (pa[59] <<< 2)  - (pa[59] <<< 4) - (pa[59] <<< 7) + (pa[59] <<< 11) - (pa[59] <<< 13);
        product[60] =                  - (pa[60] <<< 2) - (pa[60] <<< 4) + (pa[60] <<< 6) - (pa[60] <<< 8) + (pa[60] <<< 10) - (pa[60] <<< 13);
        product[61] =                  - (pa[61] <<< 2) + (pa[61] <<< 5) - (pa[61] <<< 8) - (pa[61] <<< 10) - (pa[61] <<< 12);
        product[62] = -pa[62]          - (pa[62] <<< 5) + (pa[62] <<< 8) - (pa[62] <<< 10);
        product[63] =  pa[63]          + (pa[63] <<< 4) - (pa[63] <<< 7) + (pa[63] <<< 9) + (pa[63] <<< 12);
        product[64] = -pa[64]          - (pa[64] <<< 2) - (pa[64] <<< 4) + (pa[64] <<< 7) + (pa[64] <<< 13);
        product[65] = (pa[65] <<< 1)  + (pa[65] <<< 3) - (pa[65] <<< 5) + (pa[65] <<< 7) + (pa[65] <<< 9) + (pa[65] <<< 13);
        product[66] = -pa[66]          - (pa[66] <<< 7) - (pa[66] <<< 9) - (pa[66] <<< 11) + (pa[66] <<< 13);
        product[67] =                  - (pa[67] <<< 1) - (pa[67] <<< 4) - (pa[67] <<< 9);
        product[68] =                  - (pa[68] <<< 1) + (pa[68] <<< 3) + (pa[68] <<< 8) + (pa[68] <<< 10) - (pa[68] <<< 13);
        product[69] = (pa[69] <<< 4)  - (pa[69] <<< 7) - (pa[69] <<< 9) - (pa[69] <<< 11) - (pa[69] <<< 13);
        product[70] = (pa[70] <<< 1)  + (pa[70] <<< 6) - (pa[70] <<< 8) - (pa[70] <<< 11) - (pa[70] <<< 13);
        product[71] = (pa[71] <<< 1)  - (pa[71] <<< 3) + (pa[71] <<< 5) - (pa[71] <<< 8) - (pa[71] <<< 10) - (pa[71] <<< 12);
        product[72] = -pa[72]          + (pa[72] <<< 2) + (pa[72] <<< 6) + (pa[72] <<< 9) + (pa[72] <<< 11);
        product[73] =                  - (pa[73] <<< 1) + (pa[73] <<< 6) + (pa[73] <<< 11) + (pa[73] <<< 13);
        product[74] = -pa[74]          - (pa[74] <<< 3) - (pa[74] <<< 6) - (pa[74] <<< 11) + (pa[74] <<< 14);
        product[75] =  pa[75]          - (pa[75] <<< 3) + (pa[75] <<< 6) - (pa[75] <<< 12) + (pa[75] <<< 14);
        product[76] =                  - (pa[76] <<< 1) - (pa[76] <<< 5) + (pa[76] <<< 7) + (pa[76] <<< 9) + (pa[76] <<< 12);
        product[77] =                  - (pa[77] <<< 1) + (pa[77] <<< 5) + (pa[77] <<< 7) + (pa[77] <<< 11) - (pa[77] <<< 13);
        product[78] =                  - (pa[78] <<< 2) - (pa[78] <<< 4) + (pa[78] <<< 10) - (pa[78] <<< 14);
        product[79] = -pa[79]          - (pa[79] <<< 3) + (pa[79] <<< 6) + (pa[79] <<< 8) + (pa[79] <<< 10) - (pa[79] <<< 12) - (pa[79] <<< 14);
        product[80] =  pa[80]          + (pa[80] <<< 2) + (pa[80] <<< 4) - (pa[80] <<< 9) + (pa[80] <<< 11) - (pa[80] <<< 14);
        product[81] = -pa[81]          - (pa[81] <<< 4) - (pa[81] <<< 6) + (pa[81] <<< 10) - (pa[81] <<< 12);
        product[82] = -pa[82]          - (pa[82] <<< 4) + (pa[82] <<< 6) - (pa[82] <<< 9) - (pa[82] <<< 12) + (pa[82] <<< 14);
        product[83] =  pa[83]          + (pa[83] <<< 5) - (pa[83] <<< 7) - (pa[83] <<< 9) - (pa[83] <<< 13) + (pa[83] <<< 15);
        product[84] = -pa[84]          + (pa[84] <<< 2) + (pa[84] <<< 4) - (pa[84] <<< 6) - (pa[84] <<< 8) - (pa[84] <<< 10) - (pa[84] <<< 12) + (pa[84] <<< 15);
        product[85] =                  - (pa[85] <<< 2) + (pa[85] <<< 6) + (pa[85] <<< 8) + (pa[85] <<< 11) + (pa[85] <<< 14);
        product[86] = -pa[86]          + (pa[86] <<< 2) + (pa[86] <<< 4) - (pa[86] <<< 9);
        product[87] =                  - (pa[87] <<< 7) + (pa[87] <<< 9) + (pa[87] <<< 13) - (pa[87] <<< 15);
        product[88] = (pa[88] <<< 1)  - (pa[88] <<< 3) - (pa[88] <<< 6) + (pa[88] <<< 8) - (pa[88] <<< 11) - (pa[88] <<< 13) - (pa[88] <<< 15);
        product[89] =                  - (pa[89] <<< 1) + (pa[89] <<< 7) + (pa[89] <<< 9) + (pa[89] <<< 11) + (pa[89] <<< 14) - (pa[89] <<< 16);
        product[90] =                  - (pa[90] <<< 2) - (pa[90] <<< 7) + (pa[90] <<< 9) + (pa[90] <<< 12) - (pa[90] <<< 15);
        product[91] = (pa[91] <<< 3)  - (pa[91] <<< 5) - (pa[91] <<< 7) + (pa[91] <<< 9) - (pa[91] <<< 12) + (pa[91] <<< 14);
        product[92] = (pa[92] <<< 1)  - (pa[92] <<< 6) - (pa[92] <<< 8) + (pa[92] <<< 10) + (pa[92] <<< 12) + (pa[92] <<< 16);
        product[93] = -pa[93]          + (pa[93] <<< 4) + (pa[93] <<< 6) - (pa[93] <<< 8) + (pa[93] <<< 11) + (pa[93] <<< 17);
        product[94] = (pa[94] <<< 1)  + (pa[94] <<< 4) + (pa[94] <<< 6) - (pa[94] <<< 9) - (pa[94] <<< 11) - (pa[94] <<< 13) - (pa[94] <<< 16) + (pa[94] <<< 18);
        product[95] =                  - (pa[95] <<< 1) - (pa[95] <<< 3) - (pa[95] <<< 5) + (pa[95] <<< 8) - (pa[95] <<< 10) + (pa[95] <<< 12) + (pa[95] <<< 14) - (pa[95] <<< 16) + (pa[95] <<< 18);
    end

    // ----- Combinational binary adder tree (32-bit, two's complement wrap) -----
    localparam STAGES   = $clog2(HALF);
    localparam N_PADDED = 1 << STAGES;

    reg signed [W_OUT-1:0] t0 [0:N_PADDED-1];
    reg signed [W_OUT-1:0] t1 [0:(N_PADDED/2)-1];
    reg signed [W_OUT-1:0] t2 [0:(N_PADDED/4)-1];
    reg signed [W_OUT-1:0] t3 [0:(N_PADDED/8)-1];
    reg signed [W_OUT-1:0] t4 [0:(N_PADDED/16)-1];
    reg signed [W_OUT-1:0] t5 [0:(N_PADDED/32)-1];
    reg signed [W_OUT-1:0] t6 [0:(N_PADDED/64)-1];
    reg signed [W_OUT-1:0] sum_all;

    always @(*) begin
        for (i = 0; i < HALF; i = i + 1)
            t0[i] = product[i];
        for (i = HALF; i < N_PADDED; i = i + 1)
            t0[i] = {W_OUT{1'b0}};
        for (i = 0; i < N_PADDED/2; i = i + 1)
            t1[i] = t0[2*i] + t0[2*i+1];
        for (i = 0; i < N_PADDED/4; i = i + 1)
            t2[i] = t1[2*i] + t1[2*i+1];
        for (i = 0; i < N_PADDED/8; i = i + 1)
            t3[i] = t2[2*i] + t2[2*i+1];
        for (i = 0; i < N_PADDED/16; i = i + 1)
            t4[i] = t3[2*i] + t3[2*i+1];
        for (i = 0; i < N_PADDED/32; i = i + 1)
            t5[i] = t4[2*i] + t4[2*i+1];
        for (i = 0; i < N_PADDED/64; i = i + 1)
            t6[i] = t5[2*i] + t5[2*i+1];

        sum_all = t6[0] + t6[1];
    end

    // ----- Output register -----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dout       <= {W_OUT{1'b0}};
            dout_valid <= 1'b0;
        end else begin
            dout       <= sum_all;
            dout_valid <= din_valid;
        end
    end

endmodule
