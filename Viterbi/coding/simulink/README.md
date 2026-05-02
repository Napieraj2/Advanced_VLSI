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
