# Simulink Cross-Check Model

This folder hosts a Simulink block-diagram BER tester that mirrors
[`../matlab/Viterbi_Decoder_Project.m`](../matlab/Viterbi_Decoder_Project.m): the
same `poly2trellis(3,[7 5])` convolutional code, an AWGN channel, and parallel
hard- and soft-decision Viterbi decoders sharing the trellis. It is intended as
a visual cross-check of the script's BER numbers.

## Build

The `.slx` is generated programmatically (so the repository can stay
text-friendly). From this folder, in MATLAB:

```matlab
build_viterbi_simulink_model      % creates Viterbi_Simulink_Model.slx
open_system('Viterbi_Simulink_Model')
sim('Viterbi_Simulink_Model')
disp(BER_soft); disp(BER_hard)
```

If the builder errors on `add_block` (Communications Toolbox library paths
shift between MATLAB releases), either add your release's path to the
`block_aliases()` table at the bottom of `build_viterbi_simulink_model.m`,
or assemble the model by hand using the block list below.

## Block list (manual fallback)

| Block                       | Library                                  | Key parameters                                              |
|-----------------------------|------------------------------------------|-------------------------------------------------------------|
| Bernoulli Binary Generator  | Comm Toolbox / Random Data Sources       | default                                                     |
| Convolutional Encoder       | Comm Toolbox / Convolutional Coding      | TrellisStructure = `TRELLIS`                                |
| BPSK Modulator Baseband     | Comm Toolbox / Digital Baseband / PM     | default                                                     |
| AWGN Channel                | Comm Toolbox / Channels                  | EbNo = `EbN0_dB + 10*log10(CODE_RATE)`                      |
| BPSK Demodulator Baseband   | Comm Toolbox / Digital Baseband / PM     | default                                                     |
| Quantizing Encoder          | Comm Toolbox / Source Coding             | partition = `linspace(-1,1,2^SOFT_BITS-1)`, codebook = `0:(2^SOFT_BITS-1)` |
| Viterbi Decoder (hard)      | Comm Toolbox / Convolutional Coding      | TrellisStructure = `TRELLIS`, tbdepth = `TB_DEPTH`, Hard    |
| Viterbi Decoder (soft)      | Comm Toolbox / Convolutional Coding      | TrellisStructure = `TRELLIS`, tbdepth = `TB_DEPTH`, Soft, softBits = `SOFT_BITS` |
| Error Rate Calculation × 2  | Comm Toolbox / Sinks                     | OutputData = Workspace, Variable = `BER_hard` / `BER_soft`  |

## Block diagram

```
Bernoulli ─► ConvEnc(7,5) ─► BPSK Mod ─► AWGN ─┬─► BPSK Demod ─► Viterbi (hard) ─► BER_hard
                                               └─► Quantizer  ─► Viterbi (soft) ─► BER_soft
```

Both decoders use `TB_DEPTH = 12` to match the RTL. The soft path quantizes the
AWGN output to `SOFT_BITS = 3` bits, the standard `vitdec` soft mode. The
operating point defaults to `EbN0_dB = 4`; change it in the base workspace and
re-run for a different point.

Requires Simulink, Communications Toolbox, and DSP System Toolbox.

## Cross-checking against the pipelined Verilog RTL

By default the model uses the Communications Toolbox `Viterbi Decoder` block
as a *reference* and does **not** exercise the pipelined RTL in
[`../verilog/`](../verilog/). To add HDL Cosimulation branches that drive
[`viterbi_hard_decoder.v`](../verilog/viterbi_hard_decoder.v) and
[`viterbi_soft_decoder.v`](../verilog/viterbi_soft_decoder.v) alongside the
toolbox decoders, rebuild with:

```matlab
build_viterbi_simulink_model('IncludeHDLCosim', true)
```

This adds two extra branches to the `.slx`:

```
                                           ┌─► Viterbi (toolbox, hard) ─► BER_hard
AWGN ─► BPSK Demod ─► Buffer(2) ─► (rx0,rx1)┤
                                           └─► HDL Cosim: viterbi_hard_decoder.v ─► BER_hard_rtl

                                           ┌─► Viterbi (toolbox, soft) ─► BER_soft
AWGN ─► Quantizer  ─► Buffer(2) ─► int8(±127)─►(soft0,soft1)┤
                                           └─► HDL Cosim: viterbi_soft_decoder.v ─► BER_soft_rtl
```

Two `.do` scripts are emitted next to the `.slx`:

| Script           | Purpose                                                             |
|------------------|---------------------------------------------------------------------|
| `cosim_hard.do`  | `vlog` the hard decoder, start ModelSim/Questa with cosim hooks.    |
| `cosim_soft.do`  | Same for the soft decoder.                                          |

Workflow:

```bash
# Terminal A - launch the simulator first
vsim -do cosim_hard.do          # or cosim_soft.do (one session per branch)
```

```matlab
% MATLAB - bind the HDL Cosim block to the running simulator session
% (open the block dialog once, set Connection = Socket, click 'Generate
%  connection' or run cosimWizard).  HDL Verifier dialog parameter names
% drift between releases so this step is left manual on purpose.
sim('Viterbi_Simulink_Model')
disp(BER_hard); disp(BER_hard_rtl)
disp(BER_soft); disp(BER_soft_rtl)
```

The toolbox and RTL BER readouts should match within Monte-Carlo noise; any
systematic offset usually points at a port-mapping mismatch in the HDL Cosim
block dialog (input order is `in_valid, rx0/soft0, rx1/soft1`, outputs are
`decoded_valid, decoded_bit`) or at the soft-bit centering convention
(`int8 ±127`, zero-mean) on the soft branch.

Requires HDL Verifier in addition to the toolboxes listed above, plus a
supported HDL simulator (ModelSim/Questa). The same Verilog files are also
exercised standalone by the AWGN testbenches
[`../verilog/tb_viterbi_hard_decoder_awgn.v`](../verilog/tb_viterbi_hard_decoder_awgn.v)
and
[`../verilog/tb_viterbi_soft_decoder_awgn.v`](../verilog/tb_viterbi_soft_decoder_awgn.v),
which produce a comparable BER sweep without needing HDL Verifier.
