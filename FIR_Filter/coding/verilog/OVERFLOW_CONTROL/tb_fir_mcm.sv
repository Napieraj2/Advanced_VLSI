// ============================================================================
// tb_fir_mcm.sv — Testbench for fir_mcm (OVERFLOW CONTROL variant)
// ============================================================================
`timescale 1ns / 1ps

module tb_fir_mcm;

    parameter W_IN    = 16;
    parameter W_COEFF = 21;
    parameter W_OUT   = 32;
    parameter NUM_TAPS = 192;

    reg                        clk;
    reg                        rst_n;
    reg  signed [W_IN-1:0]     din;
    reg                        din_valid;
    wire signed [W_OUT-1:0]    dout;
    wire                       dout_valid;

    // --- DUT ---
    fir_mcm #(
        .NUM_TAPS(NUM_TAPS),
        .W_IN(W_IN),
        .W_COEFF(W_COEFF),
        .W_OUT(W_OUT)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .din(din),
        .din_valid(din_valid),
        .dout(dout),
        .dout_valid(dout_valid)
    );

    // --- Clock: 10 ns period (100 MHz) ---
    initial clk = 0;
    always #5 clk = ~clk;

    // --- Stimulus ---
    integer k;
    initial begin
        $dumpfile("fir_mcm.vcd");
        $dumpvars(0, tb_fir_mcm);

        rst_n     = 0;
        din       = 0;
        din_valid = 0;

        #50;
        rst_n = 1;
        #20;

        // ----- Test 1: Impulse response -----
        @(posedge clk);
        din       = 16'sd1;
        din_valid = 1;
        @(posedge clk);
        din       = 16'sd0;

        for (k = 0; k < NUM_TAPS + 10; k = k + 1) begin
            @(posedge clk);
            if (dout_valid)
                $display("y[%0d] = %0d", k, dout);
        end

        din_valid = 0;
        #100;

        // ----- Test 2: Step response -----
        @(posedge clk);
        din_valid = 1;
        din       = 16'sd1000;
        for (k = 0; k < NUM_TAPS + 20; k = k + 1) begin
            @(posedge clk);
            if (dout_valid)
                $display("step_y[%0d] = %0d", k, dout);
        end

        din_valid = 0;
        #200;

        $display("Testbench complete.");
        $finish;
    end

endmodule
