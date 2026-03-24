// ============================================================================
// tb_fir_parallel_L3.sv — Testbench for fir_parallel_L3
// ============================================================================
// Feeds de-interleaved 3-way sample triples and verifies that the
// interleaved outputs y_0(k), y_1(k), y_2(k) reproduce the same sequence
// as fir_basic (i.e. the original 192-tap FIR impulse/step response).
// ============================================================================
`timescale 1ns / 1ps

module tb_fir_parallel_L3;

    parameter W_IN     = 16;
    parameter W_COEFF  = 21;
    parameter W_OUT    = 32;
    parameter NUM_TAPS = 192;

    reg                        clk;
    reg                        rst_n;
    reg  signed [W_IN-1:0]     din_0;
    reg  signed [W_IN-1:0]     din_1;
    reg  signed [W_IN-1:0]     din_2;
    reg                        din_valid;
    wire signed [W_OUT-1:0]    dout_0;
    wire signed [W_OUT-1:0]    dout_1;
    wire signed [W_OUT-1:0]    dout_2;
    wire                       dout_valid;

    fir_parallel_L3 #(
        .NUM_TAPS(NUM_TAPS),
        .W_IN(W_IN),
        .W_COEFF(W_COEFF),
        .W_OUT(W_OUT)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .din_0(din_0),
        .din_1(din_1),
        .din_2(din_2),
        .din_valid(din_valid),
        .dout_0(dout_0),
        .dout_1(dout_1),
        .dout_2(dout_2),
        .dout_valid(dout_valid)
    );

    // 10 ns period (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    integer k;
    integer sample_cnt;

    initial begin
`ifndef MODELSIM_VCD
        $dumpfile("fir_parallel_L3.vcd");
        $dumpvars(0, tb_fir_parallel_L3);
`endif

        rst_n     = 0;
        din_0     = 0;
        din_1     = 0;
        din_2     = 0;
        din_valid = 0;

        #50;
        rst_n = 1;
        #20;

        // =================================================================
        // Test 1: Impulse response
        // =================================================================
        // Original sequence: x = [1, 0, 0, 0, ...]
        // De-interleaved:  din_0(0)=1, din_1(0)=0, din_2(0)=0  (k=0)
        //                  all zero for k >= 1
        //
        // Expected interleaved outputs:
        //   dout_0(k) = h(3k), dout_1(k) = h(3k+1), dout_2(k) = h(3k+2)
        // =================================================================
        @(posedge clk);
        din_0     = 16'sd1;
        din_1     = 16'sd0;
        din_2     = 16'sd0;
        din_valid = 1;
        @(posedge clk);
        din_0     = 16'sd0;

        sample_cnt = 0;
        for (k = 0; k < (NUM_TAPS/3) + 10; k = k + 1) begin
            @(posedge clk);
            if (dout_valid) begin
                $display("y[%0d] = %0d  (y_0)", 3*sample_cnt,   dout_0);
                $display("y[%0d] = %0d  (y_1)", 3*sample_cnt+1, dout_1);
                $display("y[%0d] = %0d  (y_2)", 3*sample_cnt+2, dout_2);
                sample_cnt = sample_cnt + 1;
            end
        end

        din_valid = 0;
        #100;

        // =================================================================
        // Test 2: Step response  (x = [1000, 1000, 1000, ...])
        // =================================================================
        // din_0 = din_1 = din_2 = 1000
        // All three outputs should converge to sum(coeff) * 1000.
        // =================================================================
        @(posedge clk);
        din_valid = 1;
        din_0     = 16'sd1000;
        din_1     = 16'sd1000;
        din_2     = 16'sd1000;

        sample_cnt = 0;
        for (k = 0; k < (NUM_TAPS/3) + 20; k = k + 1) begin
            @(posedge clk);
            if (dout_valid) begin
                $display("step_y0[%0d] = %0d", sample_cnt, dout_0);
                $display("step_y1[%0d] = %0d", sample_cnt, dout_1);
                $display("step_y2[%0d] = %0d", sample_cnt, dout_2);
                sample_cnt = sample_cnt + 1;
            end
        end

        din_valid = 0;
        #200;

        $display("Testbench complete.");
        $finish;
    end

endmodule
