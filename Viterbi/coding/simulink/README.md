# Simulink Cross-Check Model

This folder hosts the Simulink block-diagram BER tester and the two MATLAB
sweep drivers that produce *Table 7 / Figure 3* (Simulink toolbox sweep) and
*Table 8 / Figure 4* (RTL cosim sweep) in the parent
[`../../README.md`](../../README.md). Both flows mirror
[`../matlab/Viterbi_Decoder_Project.m`](../matlab/Viterbi_Decoder_Project.m):
the same `poly2trellis(3,[7 5])` convolutional code, an AWGN channel, and
parallel hard- and soft-decision Viterbi decoders sharing the trellis. The
Simulink branch uses the Communications Toolbox `vitdec` block as an
algorithmic baseline; the RTL cosim branch drives the synthesizable Verilog
in [`../verilog/`](../verilog/) at the shipping `PIPELINE = 1, NORMALIZE = 1`
configuration.

## Files

| File | Purpose |
|---|---|
| `build_viterbi_simulink_model.m` | Programmatic `.slx` builder. Generates the model from scratch so the repo can stay text-friendly. |
| `Viterbi_Simulink_Model.slx` | Generated model (block diagram below). |
| `run_simulink_ber_sweep.m` | Sweeps `EbN0_dB` over the model, $2 \times 10^6$ bits/point. Writes `plots/simulink_ber_sweep.{csv,png}`. |
| `cosim_rtl_ber_sweep.m` | Sweeps `EbN0_dB` and drives the RTL via ModelSim batch (file I/O through `tb_viterbi_*_decoder_cosim.v`). $10^6$ bits/point. Writes `plots/cosim_rtl_ber.{csv,png}`. |
| `export_simulink_model_image.m` | Captures `plots/simulink_model.png` from the open model. |
| `plots/` | Generated artifacts referenced from the parent README (kept under version control as the canonical outputs). |

## Build the model

From this folder, in MATLAB:

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

### Block list (manual fallback)

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

### Block diagram

```
Bernoulli ─► ConvEnc(7,5) ─► BPSK Mod ─► AWGN ─┬─► BPSK Demod ─► Viterbi (hard) ─► BER_hard
                                               └─► Quantizer  ─► Viterbi (soft) ─► BER_soft
```

Both decoders use `TB_DEPTH = 12` to match the RTL. The soft path quantizes
the AWGN output to `SOFT_BITS = 3` bits, the standard `vitdec` soft mode.
Single-point operation defaults to `EbN0_dB = 4`; for a sweep, use
`run_simulink_ber_sweep.m` instead of running the model directly.

Requires Simulink, Communications Toolbox, and DSP System Toolbox.

## Toolbox BER sweep — `run_simulink_ber_sweep.m`

Drives the Simulink model above across a 0.5 dB Eb/N0 grid and writes the
results to [`plots/simulink_ber_sweep.csv`](plots/simulink_ber_sweep.csv) and
[`plots/simulink_ber_sweep.png`](plots/simulink_ber_sweep.png). This is the
*algorithmic* baseline — it exercises the toolbox `vitdec` block, not the
Verilog. See *Table 7 / Figure 3* in the parent README for the produced
numbers.

```matlab
run_simulink_ber_sweep            % uses defaults (0:0.5:8 dB, 2e6 bits/point)
```

## RTL cosim BER sweep — `cosim_rtl_ber_sweep.m`

Drives the synthesizable Verilog in [`../verilog/`](../verilog/) through
ModelSim in batch mode using the file-I/O testbenches
[`../verilog/tb_viterbi_soft_decoder_cosim.v`](../verilog/tb_viterbi_soft_decoder_cosim.v)
and
[`../verilog/tb_viterbi_hard_decoder_cosim.v`](../verilog/tb_viterbi_hard_decoder_cosim.v).
For each Eb/N0 point the script generates a single continuous stream of
`NBitsPerPoint` bits in MATLAB (BPSK + AWGN, soft-quantized to 8-bit signed
for the soft branch and sliced to ±1 for the hard branch), writes
`stim_{soft,hard}.txt`, runs ModelSim, reads back `dec_{soft,hard}.txt`, and
counts bit errors. Outputs land at
[`plots/cosim_rtl_ber.csv`](plots/cosim_rtl_ber.csv) and
[`plots/cosim_rtl_ber.png`](plots/cosim_rtl_ber.png). See *Table 8 /
Figure 4* in the parent README for the produced numbers.

```matlab
cosim_rtl_ber_sweep               % uses defaults (0:1:8 dB, 1e6 bits/point)
```

The cosim is a sign-off run of the exact RTL files that synthesize to the
shipping Quartus numbers in *Table 5* of the parent README — same source,
same `TB_DEPTH = 12`, same `NOM_LEVEL = 48` soft-quant scale. Requires
ModelSim/Questa on the path; HDL Verifier is **not** required because the
testbench-side I/O is plain `$readmemh` / `$fwrite`.

> **Note.** `matlab -batch` may print an *"Access violation detected"* dump
> from `libmwcustom_holes_factory.dll` on exit (R2025b, observed on Update 2
> and 5). The fault is in an atexit handler that runs *after*
> `cosim_rtl_ber.csv` / `.png` are written, so the outputs are correct; the
> noisy exit code can be ignored as long as the artifacts have a fresh
> timestamp.

## Optional: Simulink HDL Verifier cosim branch

`build_viterbi_simulink_model('IncludeHDLCosim', true)` adds two extra
branches to the `.slx` that drive the same Verilog files through HDL
Verifier alongside the toolbox decoders. This is **not** the path used to
produce *Table 8 / Figure 4* — that uses the file-I/O flow above, which is
faster, scriptable, and has no HDL Verifier dependency. The HDL Cosim
branches are kept as an interactive cross-check for users who already have
HDL Verifier and want to drive the RTL inside Simulink itself; they require
an HDL Verifier license, manual `cosimWizard` setup, and a separate
ModelSim session per branch. See the parameter help in
`build_viterbi_simulink_model.m` for details.
