// ============================================================================
// tb_fir_pipelined.sv — Testbench for fir_pipelined
// ============================================================================
`timescale 1ns / 1ps

module tb_fir_pipelined;

    parameter W_IN     = 16;
    parameter W_COEFF  = 21;
    parameter W_OUT    = 38;
    parameter NUM_TAPS = 192;

    reg                        clk;
    reg                        rst_n;
    reg  signed [W_IN-1:0]     din;
    reg                        din_valid;
    wire signed [W_OUT-1:0]    dout;
    wire                       dout_valid;

    fir_pipelined #(
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

    // 10 ns period (100 MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    integer k;
    integer sample_cnt;

    initial begin
        $dumpfile("fir_pipelined.vcd");
        $dumpvars(0, tb_fir_pipelined);

        rst_n     = 0;
        din       = 0;
        din_valid = 0;

        #50;
        rst_n = 1;
        #20;

        // ----- Impulse response -----
        @(posedge clk);
        din       = 16'sd1;
        din_valid = 1;
        @(posedge clk);
        din       = 16'sd0;

        sample_cnt = 0;
        for (k = 0; k < NUM_TAPS + 20; k = k + 1) begin
            @(posedge clk);
            if (dout_valid) begin
                $display("y[%0d] = %0d", sample_cnt, dout);
                sample_cnt = sample_cnt + 1;
            end
        end

        din_valid = 0;
        #100;

        // ----- Step response -----
        @(posedge clk);
        din_valid = 1;
        din       = 16'sd1000;

        sample_cnt = 0;
        for (k = 0; k < NUM_TAPS + 30; k = k + 1) begin
            @(posedge clk);
            if (dout_valid) begin
                $display("step_y[%0d] = %0d", sample_cnt, dout);
                sample_cnt = sample_cnt + 1;
            end
        end

        din_valid = 0;
        #200;

        $display("Testbench complete.");
        $finish;
    end

endmodule
