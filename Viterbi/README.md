# Advanced VLSI: Viterbi Decoder Project

## Summary

- Hard-decision and soft-decision Viterbi decoders for a rate-1/2, $K = 3$ convolutional code with generators $(7, 5)_8$.
- Both decoders share the same 4-state trellis, ACS recursion, survivor memory, and 12-symbol traceback depth.
- The final RTL configuration is `PIPELINE = 1, NORMALIZE = 1` for both variants.
- Soft decoding gives a better BER than hard, with roughly a 2 dB advantage at the same BER target.
- Synthesis is used here to compare how the architectural variants (baseline, pipelined, normalized) move $F_{\max}$, not to hit a fixed clock target; the remaining bottleneck on both final decoders is the ACS feedback loop.
- This README covers RTL implementation, simulation, Quartus synthesis, MATLAB/Simulink validation, and file-based RTL cosim BER results.

## Table of Contents

- [1. Project Overview](#1-project-overview)
- [2. Repository Structure](#2-repository-structure)
- [3. Algorithm Background](#3-algorithm-background)
- [4. Verilog Implementation](#4-verilog-implementation)
- [5. Testbench and Simulation](#5-testbench-and-simulation)
- [6. Run Instructions](#6-run-instructions)
- [7. Synthesis](#7-synthesis)
- [8. MATLAB / Simulink / RTL Cosim Results](#8-matlab--simulink--rtl-cosim-results)
- [9. Notes and Possible Extensions](#9-notes-and-possible-extensions)
- [10. References](#10-references)

## 1. Project Overview

This folder contains hard-decision and soft-decision Viterbi decoders for a rate-1/2, $K = 3$ convolutional code with generator polynomials $(7, 5)_8$. The two RTL modules ([viterbi_soft_decoder.v](coding/verilog/viterbi_soft_decoder.v) and [viterbi_hard_decoder.v](coding/verilog/viterbi_hard_decoder.v)) share the same trellis, ACS recursion, and survivor memory; they differ primarily in the branch-metric function and the input interface, which is what makes the side-by-side comparison useful.

### 1.1 Specification
The convolutional code under test is a rate-1/2, $K = 3$ encoder. *Table 1* lists the parameters used for both decoder variants.

<div align="center">

| Parameter | Value |
|---|---|
| Code rate | 1/2 |
| Constraint length $K$ | 3 |
| Generator polynomials | $g_0 = 7_8 = 111_2$, $g_1 = 5_8 = 101_2$ |
| Number of trellis states | 4 |
| Branches per state | 2 |
| Traceback depth | 12 symbols (≈ $4K$) |
| Path-metric width | 16 bits, signed |
| Soft-input width | 8 bits, signed (`viterbi_soft_decoder`) |
| Hard-input width | 1 bit per symbol coordinate (`viterbi_hard_decoder`) |
| Throughput | 1 decoded bit per clock after fill |

</div>

<div align="center">

*TABLE 1: Convolutional Code and Decoder Parameters*

</div>

## 2. Repository Structure

```
Advanced_VLSI/
├── Viterbi/
│   ├── README.md
│   ├── coding/
│   │   ├── verilog/
│   │   │   ├── viterbi_soft_decoder.v             ← Soft-decision decoder RTL (PIPELINE=1, NORMALIZE=1)
│   │   │   ├── viterbi_hard_decoder.v             ← Hard-decision decoder RTL (PIPELINE=1, NORMALIZE=1)
│   │   │   ├── tb_viterbi_soft_decoder.v          ← Soft-decision unit testbench (42-vector self-check)
│   │   │   ├── tb_viterbi_hard_decoder.v          ← Hard-decision unit testbench (42-vector self-check)
│   │   │   ├── tb_viterbi_soft_decoder_awgn.v     ← Soft AWGN BER sweep (LFSR+Box-Muller channel)
│   │   │   ├── tb_viterbi_hard_decoder_awgn.v     ← Hard AWGN BER sweep (LFSR+Box-Muller channel)
│   │   │   ├── tb_viterbi_soft_decoder_cosim.v    ← Soft cosim TB (file I/O, MATLAB-driven channel)
│   │   │   ├── tb_viterbi_hard_decoder_cosim.v    ← Hard cosim TB (file I/O, MATLAB-driven channel)
│   │   │   └── quartus/                           ← Cyclone V synthesis projects (soft + hard revisions)
│   │   ├── matlab/
│   │   │   ├── Viterbi_Decoder_Project.m          ← BER-vs-Eb/N0 sweep, soft vs hard tradeoff study
│   │   │   └── plots/
│   │   └── simulink/
│   │       ├── README.md                          ← Simulink-flow notes
│   │       ├── build_viterbi_simulink_model.m     ← Programmatic .slx builder
│   │       ├── run_simulink_ber_sweep.m           ← Toolbox BER sweep → Table 7 / Fig 3
│   │       ├── cosim_rtl_ber_sweep.m              ← RTL cosim sweep via ModelSim batch → Table 8 / Fig 4
│   │       ├── export_simulink_model_image.m      ← Block-diagram screenshot helper
│   │       ├── Viterbi_Simulink_Model.slx         ← Block-diagram BER cross-check (generated)
│   │       └── plots/                             ← simulink_ber_sweep.{png,csv}, cosim_rtl_ber.{png,csv}, simulink_model.png
│   └── Supporting Documentation/
│       ├── viterbi.pdf                            ← Viterbi 1971 IEEE paper (algorithmic reference)
│       └── Hard_and_Soft_Decision_Decoding_Using_Viterbi_Algorithm.pdf
├── .gitignore
└── LICENSE
```

## 3. Algorithm Background

### 3.1 Encoder and Trellis
The encoder is a rate-1/2, $K = 3$ convolutional encoder driven by a 2-bit shift register $(s_1, s_0)$ holding the previous two input bits. With current input $u_n$, the two coded output bits per input come from generators $g_0 = 7_8$ and $g_1 = 5_8$:

$$c_0(n) = u_n \oplus s_1 \oplus s_0$$
(*Equation 1*)

$$c_1(n) = u_n \oplus s_0$$
(*Equation 2*)

The register advances to $(u_n, s_1)$, giving $2^{K-1} = 4$ trellis states with two branches in and two branches out per state — the four-state butterfly on which ACS runs. The same `enc_out` function is used by the testbench and by the decoder's branch expansion, guaranteeing consistency.

### 3.2 Branch Metric
The soft and hard decoders differ only in this step. For expected coded pair $(e_1, e_0)$, soft inputs $r_0, r_1$ (signed, zero-centered) give a dot product (*Equation 3*); hard inputs $\hat{r}_0, \hat{r}_1$ (single bits) give a $\{+1, -1\}$ agreement count equivalent to negative Hamming distance (*Equation 4*). Both are oriented so larger is better, so the rest of the ACS pipeline is identical.

$$BM_{\mathrm{soft}} = (2e_1 - 1) \cdot r_0 + (2e_0 - 1) \cdot r_1$$
(*Equation 3*)

$$BM_{\mathrm{hard}} = (2e_1 - 1)(2\hat{r}_0 - 1) + (2e_0 - 1)(2\hat{r}_1 - 1)$$
(*Equation 4*)

### 3.3 Add-Compare-Select
For each destination state $d$ at symbol time $n$, the ACS step takes the two incoming branches from predecessor states $p_0$ and $p_1$, adds the branch metric, and keeps the larger candidate, as shown in *Equations 5* and *6*.

$$M'(d) = \max\Bigl(M(p_0) + BM(p_0 \to d),\ M(p_1) + BM(p_1 \to d)\Bigr)$$
(*Equation 5*)

$$\mathrm{survivor}(d) = \arg\max\Bigl(M(p_0) + BM(p_0 \to d),\ M(p_1) + BM(p_1 \to d)\Bigr)$$
(*Equation 6*)

To handle the cold-start case, only state 0 is initialized to $M = 0$ and the other three states start at `METRIC_MIN = -(2^{15}-1)`. Branches whose predecessor sits at `METRIC_MIN` are skipped, so the trellis can only be entered from state 0 at $n = 0$. This avoids spurious survivors during the initial fill window.

### 3.4 Survivor Memory and Traceback
A 2-D survivor history of depth `TB_DEPTH = 12` records, for every state and every recent symbol, the predecessor state and the input bit that won the ACS at that step. Each cycle the entire history is shifted by one column, and the new ACS results are written into column 0. After the recursion, the decoder picks the state with the highest current path metric and walks backward 12 steps along its survivor pointers. The bit emitted at the deepest step is taken as the decoded output.

Twelve symbols is roughly four constraint lengths, which is the conventional rule of thumb for Viterbi traceback depth. It is deep enough that nearly all surviving paths have merged by the time the decoder commits, but shallow enough that the survivor RAM and traceback logic stay small.

## 4. Verilog Implementation

Both decoders are written as a single combinational `next_*` block plus a registered update block. The same structure serves both metric variants. *Table 2* maps the major sections of the RTL to their algorithmic role.

<div align="center">

| Section | Role |
|---|---|
| `enc_out` function | Branch labeling: matches encoder for trellis expansion |
| `branch_metric` function | Soft dot-product or hard agreement count |
| ACS loop over `(s, b)` | Computes candidate metrics and selects per-state survivor |
| Survivor shift loop | Shifts `survivor_prev`/`survivor_bit` history by one column |
| Best-state search | Picks max-metric state for traceback start |
| Traceback loop | Walks 12 steps back along survivor pointers |
| Sequential block | Updates path metrics, survivor RAM, output registers |

</div>

<div align="center">

*TABLE 2: Decoder RTL Section Map*

</div>

### 4.1 Soft Decoder (`viterbi_soft_decoder.v`)
Parameterized by `SOFT_W` (default 8, inputs span $[-127, +127]$) and `METRIC_W` (default 16). The branch metric is bounded by $\pm 2 \cdot (2^{SOFT_W-1}-1)$ per symbol, so the 16-bit path metric does not reach `METRIC_MIN` over a 12-symbol traceback window. Decoded output appears one cycle after ACS, with `decoded_valid` asserting once `sym_count` reaches `TB_DEPTH-1`. Normalization uses the **in-cycle** form (see §4.3).

### 4.2 Hard Decoder (`viterbi_hard_decoder.v`)
Replaces the soft input ports with two single-bit symbol pins (`rx0`, `rx1`); branch metrics collapse to the set $\{-2, 0, +2\}$. The 16-bit path-metric width is kept for parameter symmetry with the soft variant. ACS, survivor shift, traceback, and output handshake are identical to the soft version. Normalization uses the **pipelined-offset** form (see §4.3).

### 4.3 Path-Metric Normalization

`NORMALIZE = 1` (default on both decoders) keeps registered path metrics bounded on continuous streams; without it the 16-bit signed metric wraps (after roughly $2^{15}/2 \approx 16{,}000$ symbols on the hard decoder, faster on the soft decoder), which corrupted the high-SNR tail of the §8.3 cosim curve until normalization was enabled. Argmax is invariant under a constant offset, so on short AWGN runs (*Tables 3b/c*) — i.e., before any un-normalized overflow — decoded output is bit-exact to `NORMALIZE = 0`. States pinned at `METRIC_MIN` during cold-start fill are left alone so the guard keeps working. The two variants use different placements:

<div align="center">

| | Soft decoder (in-cycle) | Hard decoder (pipelined-offset) |
|---|---|---|
| Placement | Min reduction + per-state subtract in series with ACS comparator | Min reduction over *registered* `path_metric[]`, captured in `min_offset_q`, subtracted next cycle |
| Why this form | Pipelined-offset recurrence overflows at $\pm 254$ BM scale within $10^5$–$5\times 10^5$ symbols (random walk) | Bounded $\{-2, 0, +2\}$ BM keeps the residual oscillation well inside 16-bit signed |
| $F_{\max}$ impact | Adds one adder layer to ACS path (~16 MHz cost, §7.2) | Min reduction parallel to ACS; baseline $F_{\max}$ essentially unchanged |

</div>

<div align="center">

*TABLE 2a: Normalization Form per Decoder*

</div>

### 4.4 Architectural Differences Between the Two Decoders
The two decoders share the same RTL structure; only the branch-metric path differs. *Table 2b* lists the differences that show up in synthesis.

<div align="center">

| Aspect | Soft Decoder | Hard Decoder |
|---|---|---|
| Input type | `soft0`, `soft1`, each `signed [SOFT_W-1:0]` (default 8 b, range $[-127, +127]$) | `rx0`, `rx1`, each one bit |
| Branch metric | Signed dot product (*Eq. 3*) | $\pm 1$ agreement count, $\{-2, 0, +2\}$ (*Eq. 4*) |
| Branch-metric range per symbol | $\pm 2 \cdot (2^{SOFT_W-1}-1) = \pm 254$ | $\pm 2$ |
| Normalization style | In-cycle subtract-min (§4.3) | Pipelined offset (§4.3) |
| Main synthesis consequence | Wider, more uniform datapath; higher baseline $F_{\max}$, soft-side $F_{\max}$ ceiling set by in-cycle min reduction | Small adders pack onto long carry chains, hurting baseline $F_{\max}$; pipeline cut + parallel min reduction recovers it |

</div>

<div align="center">

*TABLE 2b: Soft vs Hard — Architectural Differences*

</div>

## 5. Testbench and Simulation

Both testbenches share the same structure, summarized in *Table 3a*. The differences are isolated in the channel model and the input port set.

<div align="center">

| Parameter | Value |
|---|---|
| Clock | 100 MHz (10 ns period) |
| Reset | `rst_n` held low for 4 clocks, released before any data |
| Message length | 40 random bits |
| Tail bits | 2 zero bits to flush the encoder |
| Total transmitted bits | 42 |
| Drain symbols | `TB_DEPTH + 4 = 16` zero symbols to flush traceback |
| Pass criterion | `err_count == 0` over all 42 decoded bits |
| VCD dump | Enabled for both designs |

</div>

<div align="center">

*TABLE 3a: Common Simulation Conditions*

</div>

### 5.1 Unit-Test Channel Models

The **soft** unit-test channel maps each encoded bit to a nominal soft level of $+48$ for `1` and $-48$ for `0`, then perturbs it with a uniform integer noise sample on $[-6, +6]$ (centered by subtracting 6 from `|$random| % 13`). The result fits inside the 8-bit signed range and gives the soft decoder enough margin to reach zero bit errors per run. The noise model is intentionally simple and is not a true AWGN process; it confirms that the soft branch metric is integrating evidence rather than committing on individual symbols.

The **hard** unit-test channel applies independent bit flips to each of the two coded coordinates with probability 8% per coordinate; 12 symbols of traceback is enough to absorb that level of noise on the short 42-bit message without uncorrectable errors.

### 5.2 RTL AWGN BER Sanity Sweeps

Two companion testbenches ([tb_viterbi_soft_decoder_awgn.v](coding/verilog/tb_viterbi_soft_decoder_awgn.v) and [tb_viterbi_hard_decoder_awgn.v](coding/verilog/tb_viterbi_hard_decoder_awgn.v)) drive the DUTs against a true AWGN channel built from two 32-bit Galois LFSRs (CRC-32 polynomial) feeding a Box-Muller transform. Each coded bit is modulated to $\pm \mathrm{NOM\_LEVEL} + \sigma \cdot z$ with $\sigma = \mathrm{NOM\_LEVEL} / \sqrt{2 \cdot 10^{(E_b/N_0 - 3.01)/10}}$ (the 3.01 dB term is the rate-1/2 $E_s/E_b$ correction). The soft testbench saturate-quantizes to signed 8-bit; the hard testbench hard-slices the same noisy sample at zero before driving `rx0`/`rx1`. Both sweep $E_b/N_0 = 0\dots 8$ dB in 1 dB steps and run `TRIALS_PER_POINT = 50` independent 100-bit trials per point (5000 bits total) with a full DUT reset between trials, so the soft and hard tables are directly comparable on the same noise process. The trial structure predates `NORMALIZE = 1` and is kept so the unit-test sweep stays self-contained; the long continuous-stream sweep uses the cosim flow in §8.3.

<div align="center">

| $E_b/N_0$ (dB) | $\sigma$ | bits | errors | BER |
|---:|---:|---:|---:|---:|
| 0.0 | 48.000 | 5000 |  433 | $8.66 \times 10^{-2}$ |
| 1.0 | 42.780 | 5000 |  209 | $4.18 \times 10^{-2}$ |
| 2.0 | 38.128 | 5000 |  113 | $2.26 \times 10^{-2}$ |
| 3.0 | 33.981 | 5000 |   69 | $1.38 \times 10^{-2}$ |
| 4.0 | 30.286 | 5000 |   26 | $5.20 \times 10^{-3}$ |
| 5.0 | 26.992 | 5000 |    7 | $1.40 \times 10^{-3}$ |
| 6.0 | 24.057 | 5000 |    4 | $8.00 \times 10^{-4}$ |
| 7.0 | 21.441 | 5000 |    0 | 0 observed (< $2.0 \times 10^{-4}$ resolution) |
| 8.0 | 19.109 | 5000 |    0 | 0 observed (< $2.0 \times 10^{-4}$ resolution) |

</div>

<div align="center">

*TABLE 3b: AWGN BER Sweep — Soft Decoder*

</div>

<div align="center">

| $E_b/N_0$ (dB) | $\sigma$ | bits | errors | BER |
|---:|---:|---:|---:|---:|
| 0.0 | 48.000 | 5000 | 1039 | $2.08 \times 10^{-1}$ |
| 1.0 | 42.780 | 5000 |  659 | $1.32 \times 10^{-1}$ |
| 2.0 | 38.128 | 5000 |  376 | $7.52 \times 10^{-2}$ |
| 3.0 | 33.981 | 5000 |  205 | $4.10 \times 10^{-2}$ |
| 4.0 | 30.286 | 5000 |   85 | $1.70 \times 10^{-2}$ |
| 5.0 | 26.992 | 5000 |   64 | $1.28 \times 10^{-2}$ |
| 6.0 | 24.057 | 5000 |   45 | $9.00 \times 10^{-3}$ |
| 7.0 | 21.441 | 5000 |    8 | $1.60 \times 10^{-3}$ |
| 8.0 | 19.109 | 5000 |    6 | $1.20 \times 10^{-3}$ |

</div>

<div align="center">

*TABLE 3c: AWGN BER Sweep — Hard Decoder*

</div>

> **Caveat (referenced as "short RTL sanity check" elsewhere in this report).** Rows reported as `0 observed` mean zero errors over the finite 5000-bit run length, not proof of zero BER. *Tables 3b/c* are intended to catch gross RTL/channel bugs and verify the soft-vs-hard ordering; absolute values should be cross-referenced against *Table 7* (Simulink, $2 \times 10^6$ bits) and *Table 8* (RTL cosim, $10^6$ bits) for any quantitative use. The Box-Muller block uses simulation-only system functions (`$ln`, `$sqrt`, `$cos`, `$sin`) and is a verification model, not synthesizable RTL.

### 5.3 Pass/Fail Reporting
Both testbenches register decoded bits as they arrive against the original `tx_bits` array and increment `err_count` on every mismatch. After the drain phase, the testbench prints the number of bits checked, the error count, and either `PASS` or `FAIL`.

## 6. Run Instructions

### 6.1 Prerequisites

| Tool | Used for | Required? |
|---|---|---|
| ModelSim or Questa | Verilog simulation (unit TBs, AWGN TBs, cosim TBs) | Yes |
| Quartus Prime Lite 25.1 (or compatible) | Cyclone V synthesis (§7) | Yes, for synthesis |
| MATLAB with Communications Toolbox | MATLAB BER sweep (§8) and file-based RTL cosim driver (§8.3) | Yes, for MATLAB / cosim flows |
| Simulink | Block-diagram BER cross-check (§8.2) | Yes, for §8.2 only |
| HDL Verifier | Optional live HDL cosimulation branch in `build_viterbi_simulink_model.m` (`IncludeHDLCosim`) | Optional |

The file-based RTL cosim flow in §8.3 uses MATLAB plus a batch ModelSim invocation (`vlog` + `vsim -c`) and exchanges stimulus/response through plain text files. It does **not** require an HDL Verifier license or a live cosim socket.

### 6.2 Verilog Simulation (ModelSim / Questa)

All Verilog commands run from `Viterbi/coding/verilog/`:

```bash
cd Viterbi/coding/verilog
```

#### Unit tests

42-vector self-checking testbenches; expected output is a final summary line such as `bits checked = 42, errors = 0 -> PASS`:

```bash
vlog viterbi_soft_decoder.v tb_viterbi_soft_decoder.v
vsim -c tb_viterbi_soft_decoder -do "run -all; quit -f"

vlog viterbi_hard_decoder.v tb_viterbi_hard_decoder.v
vsim -c tb_viterbi_hard_decoder -do "run -all; quit -f"
```

#### RTL AWGN BER sanity sweeps

Short 5000-bit-per-point sweeps over $E_b/N_0 = 0\dots 8$ dB; expected output is one BER line per Eb/N0 point (see *Tables 3b* and *3c* — short RTL sanity checks):

```bash
vlog viterbi_soft_decoder.v tb_viterbi_soft_decoder_awgn.v
vsim -c tb_viterbi_soft_decoder_awgn -do "run -all; quit -f"

vlog viterbi_hard_decoder.v tb_viterbi_hard_decoder_awgn.v
vsim -c tb_viterbi_hard_decoder_awgn -do "run -all; quit -f"
```

### 6.3 Quartus Synthesis

From [Viterbi/coding/verilog/quartus/](coding/verilog/quartus), either revision can be compiled standalone (full setup is described in §7.1):

```bash
quartus_sh --flow compile viterbi_soft
quartus_sh --flow compile viterbi_hard
quartus_sta -t critical_path_extract.tcl viterbi_soft
quartus_sta -t critical_path_extract.tcl viterbi_hard
```

### 6.4 MATLAB BER Sweep

```matlab
cd Viterbi/coding/matlab
Viterbi_Decoder_Project       % BER sweep, plot, coding-gain table
```

### 6.5 Simulink BER Sweep

```matlab
cd Viterbi/coding/simulink
build_viterbi_simulink_model  % regenerates Viterbi_Simulink_Model.slx
run_simulink_ber_sweep        % toolbox sweep -> Table 7 / Figure 3
```

### 6.6 File-Based RTL Cosim Sweep

Drives the actual `PIPELINE = 1, NORMALIZE = 1` RTL through a continuous-stream channel (no HDL Verifier license required). Produces [cosim_rtl_ber.csv](coding/simulink/plots/cosim_rtl_ber.csv) and [cosim_rtl_ber.png](coding/simulink/plots/cosim_rtl_ber.png):

```matlab
cd Viterbi/coding/simulink
cosim_rtl_ber_sweep
```

## 7. Synthesis

The two decoders were pushed through the same Cyclone V flow as the FIR sub-project, with one Quartus *revision* per metric variant living under [Viterbi/coding/verilog/quartus/](coding/verilog/quartus). The intent is timing/area characterization only — there are no pin assignments or board bring-up artifacts; everything except `clk` is declared as a virtual pin in each `.qsf`.

### 7.1 Project Setup

<div align="center">

| Item | Value |
|---|---|
| Family / Device | Cyclone V `5CGXFC9E7F35C8` |
| Quartus version | 25.1 Lite |
| SDC reference clock | 100 MHz (`viterbi.sdc`, identical to `fir.sdc`) — used only as a fixed reference for slack reporting; not a project requirement |
| Revisions | `viterbi_soft` (top: `viterbi_soft_decoder`)<br>`viterbi_hard` (top: `viterbi_hard_decoder`) |
| Shared SDC | [viterbi.sdc](coding/verilog/quartus/viterbi.sdc) — 100 MHz clock, 5.0/0.0 ns I/O delay, false-path on `rst_n` |
| Critical-path script | [critical_path_extract.tcl](coding/verilog/quartus/critical_path_extract.tcl) |

</div>

<div align="center">

*TABLE 4: Quartus Project Setup*

</div>

From the [quartus/](coding/verilog/quartus) folder, either revision can be compiled standalone:

```bash
quartus_sh --flow compile viterbi_soft
quartus_sh --flow compile viterbi_hard
quartus_sta -t critical_path_extract.tcl viterbi_soft
quartus_sta -t critical_path_extract.tcl viterbi_hard
```

### 7.2 Post-Fit Results

Numbers below are read from `output_files/<rev>.fit.summary` and the Slow 1100 mV 85 °C corner of `<rev>.sta.rpt`. Each revision was fit twice: `PIPELINE = 0, NORMALIZE = 0` (baseline) and `PIPELINE = 1, NORMALIZE = 1` (final RTL configuration; see §4.1–§4.3). The pipeline cuts are asymmetric — hard adds an input-side register only, soft adds the same input register plus retiming of the best-state max and 12-deep traceback to read the *registered* `path_metric`/`survivor_*` arrays. The extra logic is fenced behind `// === PIPELINE additions ===` and `// === NORMALIZE ===` blocks, so the baseline column reproduces the original synthesis exactly.

<div align="center">

| Metric | `viterbi_soft` (baseline) | `viterbi_soft` (final) | `viterbi_hard` (baseline) | `viterbi_hard` (final) |
|---|---|---|---|---|
| ALMs (Logic utilization) | 410 / 113,560 ($<$ 1 %) | 608 / 113,560 ($<$ 1 %) | 346 / 113,560 ($<$ 1 %) | 500 / 113,560 ($<$ 1 %) |
| Total registers | 211 | 231 | 192 | 233 |
| Total virtual pins | 20 | 20 | 6 | 6 |
| Block memory bits | 0 | 0 | 0 | 0 |
| RAM blocks | 0 | 0 | 0 | 0 |
| DSP blocks | 0 | 0 | 0 | 0 |
| Slow 85 °C $F_{\max}$ | **32.32 MHz** | **34.01 MHz** | **23.64 MHz** | **32.32 MHz** |
| Slow 85 °C setup slack vs 100 MHz SDC reference | $-20.94$ ns | $-19.40$ ns | $-32.30$ ns | $-20.94$ ns |
| Slow 85 °C hold slack | $-10.74$ ns | $-10.35$ ns | $-10.05$ ns | $-9.97$ ns |
| Decode latency | $TB\_DEPTH$ cycles | $TB\_DEPTH + 2$ cycles | $TB\_DEPTH$ cycles | $TB\_DEPTH + 1$ cycles |
| Fitter status | Successful | Successful | Successful | Successful |

</div>

<div align="center">

*TABLE 5: Post-Fit Synthesis Results — Baseline vs Final RTL Configuration*

</div>

> **Note on timing reporting.** These Quartus builds are characterization builds, not timing-clean board-ready implementations. The 100 MHz SDC clock is used as a fixed reference for comparing setup slack and $F_{\max}$ across variants, not as a project requirement. The negative hold slack should likewise be treated as a characterization/constraint issue that would need to be resolved before board deployment — a successful fitter status here does not imply timing closure. The virtual-pin setup is used only for relative area/timing comparison.

The area increase is driven almost entirely by `NORMALIZE = 1` on both decoders (§4.3). An intermediate ACS-only fit with `PIPELINE = 1, NORMALIZE = 0` (not shown in *Table 5*) measured soft = 50.10 MHz and hard = 32.67 MHz, which bounds the timing cost of normalization at ~16 MHz on the soft decoder and effectively zero on the hard decoder. That intermediate configuration is **not** the final continuous-stream-safe RTL.

The two decoders react differently to the `PIPELINE = 1` retime because their critical paths live in different places:

<div align="center">

| | Hard decoder | Soft decoder |
|---|---|---|
| Critical path before pipeline | Input pins → ACS comparator (BMU is $\pm 1$, cone is narrow) | ACS → 4-way max → 12-deep traceback (combinational cone, not the input pins) |
| What pipelining cuts | Input-side register breaks the path; deeper retiming not needed | Input register alone *hurt* (32.32 → 28.72 MHz interim); also retime best-state max and traceback to read registered `path_metric`/`survivor_*` |
| Final $F_{\max}$ ceiling | ACS feedback loop | ACS feedback loop + in-cycle min reduction (drops 50.10 → 34.01 MHz) |

</div>

Across all variants the remaining critical path on both decoders is the ACS feedback loop itself, which can only be sliced by changing the algorithm. See §9 for the next options.

## 8. MATLAB / Simulink / RTL Cosim Results

A Communications Toolbox script under [Viterbi/coding/matlab/](coding/matlab) re-implements the same code with `poly2trellis(3,[7 5])` and runs a BER-vs-$E_b/N_0$ sweep over an AWGN channel using `vitdec` in both `'hard'` and `'soft'` modes (3-bit soft quantization, traceback depth 12 — same as the RTL). A Simulink companion in [Viterbi/coding/simulink/](coding/simulink) wraps the same trellis in a block-diagram model and produces independent BER readouts as a cross-check. Run instructions are in §6.4–§6.6.

The BER sweep is shown in *Figure 1*. The soft and hard curves match the prediction for this code: the soft decoder sits roughly 2 dB to the left of the hard decoder, and both sit well to the left of uncoded BPSK over the simulated $E_b/N_0$ range.

<p align="center"><img src="coding/matlab/plots/ber_soft_vs_hard.png" alt="BER vs Eb/N0"></p>

<div align="center">

*FIGURE 1: BER vs $E_b/N_0$ — Soft vs Hard vs Uncoded BPSK*

</div>

### 8.1 Combined Tradeoff View

Layering the synthesis numbers from §7 onto the BER results gives the area/timing-vs-channel-performance view this study was after. *Table 6* focuses on the final RTL configuration; baseline numbers are in *Table 5*.

<div align="center">

| Decoder (final RTL) | ALMs | Regs | $F_{\max}$ (slow 85 °C) | $E_b/N_0$ @ BER $= 10^{-4}$ | Coding gain vs uncoded |
|---|---|---|---|---|---|
| Soft† | 608 | 231 | 34.01 MHz | $\approx 5.5$ dB | $\approx 3$ dB |
| Hard | 500 | 233 | 32.32 MHz | $\approx 7.5$ dB | $\approx 1$ dB |

</div>

<div align="center">

*TABLE 6: Final-RTL Hardware/Channel Tradeoff*

</div>

> †Hardware area and timing are for the default 8-bit signed soft-input RTL. The BER operating point comes from the MATLAB/Simulink 3-bit soft-decision reference unless otherwise noted; the file-based RTL cosim sweep in §8.3 uses the 8-bit RTL directly.

Compared with the final hard decoder, the final soft decoder buys roughly 2 dB of BER advantage at the cost of about 22 % more ALMs (608 vs 500). Within the soft decoder itself, in-cycle normalization reduces the intermediate `PIPELINE = 1, NORMALIZE = 0` $F_{\max}$ (50.10 MHz) by about 16 MHz to the final 34.01 MHz, setting the soft-side timing ceiling. Pushing $F_{\max}$ further requires breaking the ACS feedback loop itself; see §9.

### 8.2 Simulink Cross-Check

The Simulink companion model lives in [Viterbi/coding/simulink/](coding/simulink) and is rebuilt programmatically from [build_viterbi_simulink_model.m](coding/simulink/build_viterbi_simulink_model.m). It does not import the Verilog RTL — the Communications Toolbox `Viterbi Decoder` block is used as an independent reference for the same trellis (`poly2trellis(3,[7 5])`, `TB_DEPTH = 12`) so the BER results in §8 can be cross-validated against a second, fully independent implementation. The block diagram is shown in *Figure 2*.

<p align="center"><img src="coding/simulink/plots/simulink_model.png" alt="Simulink Viterbi model"></p>

<div align="center">

*FIGURE 2: Simulink Model Block Diagram*

</div>

The AWGN block uses `Variance = 1/(R·10^(EbN0_dB/10))`. Because the BPSK output is complex and the demod chain uses only the real component, the effective real-axis variance is half that value, matching the $N_0/2$ convention used in the MATLAB and RTL AWGN flows. The same `EbN0_dB` workspace variable drives the MATLAB and Simulink sweeps. *Table 7* lists the BER produced by [run_simulink_ber_sweep.m](coding/simulink/run_simulink_ber_sweep.m) over a 0.5 dB grid with $2 \times 10^6$ data bits per point.

<div align="center">

| $E_b/N_0$ (dB) | bits | err_soft | BER_soft | err_hard | BER_hard |
|---:|---:|---:|---:|---:|---:|
| 0.0 | 2,000,001 | 226,216 | $1.13 \times 10^{-1}$ | 398,542 | $1.99 \times 10^{-1}$ |
| 0.5 | 2,000,001 | 161,560 | $8.08 \times 10^{-2}$ | 329,904 | $1.65 \times 10^{-1}$ |
| 1.0 | 2,000,001 | 108,398 | $5.42 \times 10^{-2}$ | 261,957 | $1.31 \times 10^{-1}$ |
| 1.5 | 2,000,001 |  69,381 | $3.47 \times 10^{-2}$ | 202,827 | $1.01 \times 10^{-1}$ |
| 2.0 | 2,000,001 |  39,256 | $1.96 \times 10^{-2}$ | 147,456 | $7.37 \times 10^{-2}$ |
| 2.5 | 2,000,001 |  21,414 | $1.07 \times 10^{-2}$ | 102,009 | $5.10 \times 10^{-2}$ |
| 3.0 | 2,000,001 |  10,247 | $5.12 \times 10^{-3}$ |  66,143 | $3.31 \times 10^{-2}$ |
| 3.5 | 2,000,001 |   4,597 | $2.30 \times 10^{-3}$ |  41,034 | $2.05 \times 10^{-2}$ |
| 4.0 | 2,000,001 |   1,930 | $9.65 \times 10^{-4}$ |  23,945 | $1.20 \times 10^{-2}$ |
| 4.5 | 2,000,001 |     697 | $3.49 \times 10^{-4}$ |  12,816 | $6.41 \times 10^{-3}$ |
| 5.0 | 2,000,001 |     203 | $1.02 \times 10^{-4}$ |   6,509 | $3.25 \times 10^{-3}$ |
| 5.5 | 2,000,001 |      68 | $3.40 \times 10^{-5}$ |   3,032 | $1.52 \times 10^{-3}$ |
| 6.0 | 2,000,001 |      11 | $5.50 \times 10^{-6}$ |   1,253 | $6.27 \times 10^{-4}$ |
| 6.5 | 2,000,001 |      10 | $5.00 \times 10^{-6}$ |     526 | $2.63 \times 10^{-4}$ |
| 7.0 | 2,000,001 |       0 | 0 observed                | 182 | $9.10 \times 10^{-5}$ |
| 7.5 | 2,000,001 |       0 | 0 observed                |  70 | $3.50 \times 10^{-5}$ |
| 8.0 | 2,000,001 |       0 | 0 observed                |  13 | $6.50 \times 10^{-6}$ |

</div>

<div align="center">

*TABLE 7: Simulink BER Sweep*

</div>

Rows listed as `0 observed` mean zero observed errors over the finite $2 \times 10^6$-bit run length (resolution $< 5.0 \times 10^{-7}$), not proof of zero BER.

The BER curve is plotted in *Figure 3*.

<p align="center"><img src="coding/simulink/plots/simulink_ber_sweep.png" alt="Simulink BER vs Eb/N0"></p>

<div align="center">

*FIGURE 3: Simulink BER vs $E_b/N_0$*

</div>

The model has an optional `IncludeHDLCosim` flag in [build_viterbi_simulink_model.m](coding/simulink/build_viterbi_simulink_model.m) that adds two HDL Cosimulation branches alongside the toolbox decoders so the RTL `viterbi_soft_decoder.v` / `viterbi_hard_decoder.v` can be co-simulated in-place against the same channel. That path is off by default because it requires a ModelSim/Questa license configured for HDL Verifier; the toolbox-only branches above are sufficient for the BER cross-check.

### 8.3 RTL Cosim BER (file-based, no HDL Verifier license)

For users without an HDL Verifier checkout, [cosim_rtl_ber_sweep.m](coding/simulink/cosim_rtl_ber_sweep.m) runs the *actual final RTL* through the same Simulink-style channel chain (BPSK + AWGN, signed 8-bit soft quantization at `NOM_LEVEL = 48`) with file-based I/O — no live cosim socket and no HDL Verifier license required.

<div align="center">

| Stage | Action |
|---|---|
| 1. MATLAB | Generates one continuous payload per Eb/N0 point + AWGN-quantized soft samples (and matching hard slice); writes `stim_soft.txt` / `stim_hard.txt` |
| 2. ModelSim (batch) | Runs [tb_viterbi_soft_decoder_cosim.v](coding/verilog/tb_viterbi_soft_decoder_cosim.v) / [tb_viterbi_hard_decoder_cosim.v](coding/verilog/tb_viterbi_hard_decoder_cosim.v) via `vlog` + `vsim -c` against the same final RTL as *Table 5*; writes one decoded bit per line to `dec_*.txt` |
| 3. MATLAB | Reads decoded bits, computes BER, writes [cosim_rtl_ber.csv](coding/simulink/plots/cosim_rtl_ber.csv) and [cosim_rtl_ber.png](coding/simulink/plots/cosim_rtl_ber.png) |

</div>

Because `NORMALIZE = 1` on both decoders (§4.3), each Eb/N0 point runs as a single continuous $10^6$-bit payload with one cold-start reset — no intra-point trial resets, no metric saturation, so the high-SNR results reflect continuous-stream behavior rather than metric wraparound.

<div align="center">

| $E_b/N_0$ (dB) | bits | err_soft | BER_soft_rtl | err_hard | BER_hard_rtl |
|---:|---:|---:|---:|---:|---:|
| 0.0 | 1,000,000 | 95,402 | $9.54 \times 10^{-2}$ | 198,227 | $1.98 \times 10^{-1}$ |
| 1.0 | 1,000,000 | 44,293 | $4.43 \times 10^{-2}$ | 132,490 | $1.32 \times 10^{-1}$ |
| 2.0 | 1,000,000 | 15,471 | $1.55 \times 10^{-2}$ |  74,237 | $7.42 \times 10^{-2}$ |
| 3.0 | 1,000,000 |  3,947 | $3.95 \times 10^{-3}$ |  33,902 | $3.39 \times 10^{-2}$ |
| 4.0 | 1,000,000 |    671 | $6.71 \times 10^{-4}$ |  12,034 | $1.20 \times 10^{-2}$ |
| 5.0 | 1,000,000 |     86 | $8.60 \times 10^{-5}$ |   3,413 | $3.41 \times 10^{-3}$ |
| 6.0 | 1,000,000 |      8 | $8.00 \times 10^{-6}$ |     690 | $6.90 \times 10^{-4}$ |
| 7.0 | 1,000,000 |      1 | $1.00 \times 10^{-6}$ |     111 | $1.11 \times 10^{-4}$ |
| 8.0 | 1,000,000 |      0 | 0 observed            |      15 | $1.50 \times 10^{-5}$ |

</div>

<div align="center">

*TABLE 8: RTL Cosim BER Sweep*

</div>

Rows listed as `0 observed` mean zero observed errors over the finite $10^6$-bit run length (resolution $< 1.0 \times 10^{-6}$), not proof of zero BER.

The BER curve is plotted in *Figure 4*.

<p align="center"><img src="coding/simulink/plots/cosim_rtl_ber.png" alt="RTL cosim BER vs Eb/N0"></p>

<div align="center">

*FIGURE 4: RTL Cosim BER vs $E_b/N_0$*

</div>

The RTL soft curve is slightly better than the toolbox 3-bit curve in *Figure 3* because the RTL consumes signed 8-bit soft samples directly while the Simulink branch pays a quantization penalty for the 3-bit soft input (§8.2). Hard agrees within Monte-Carlo noise.

> **Note.** `matlab -batch` may print an *"Access violation detected"* dump from `libmwcustom_holes_factory.dll` on exit (R2025b, observed on Update 2 and 5). The exit fault occurs *after* `cosim_rtl_ber.csv` / `.png` are written, so the artifacts themselves are correct; verify fresh timestamps on the output files before using the results.

### 8.4 Final Design State and Cross-Tool Trend Check

The final RTL configuration is `PIPELINE = 1, NORMALIZE = 1` on both decoders, with the asymmetric normalization placement documented in §4.3. Every artifact in this report was generated against that same RTL on May 2, 2026. *Table 8b* summarizes four decoder/Eb/N0 comparison cells at 4 dB and 6 dB.

<div align="center">

| Source | Tool | Soft @ 4 dB | Soft @ 6 dB | Hard @ 4 dB | Hard @ 6 dB | Notes |
|---|---|---:|---:|---:|---:|---|
| MATLAB `vitdec` (*Fig. 1*) | Comm Toolbox | $8.69 \times 10^{-4}$ | $1.70 \times 10^{-5}$ | $1.18 \times 10^{-2}$ | $6.44 \times 10^{-4}$ | $10^6$ bits, 3-bit soft — high-statistics reference |
| Simulink (*Table 7*) | Simulink + `vitdec` | $9.65 \times 10^{-4}$ | $5.50 \times 10^{-6}$ | $1.20 \times 10^{-2}$ | $6.27 \times 10^{-4}$ | $2 \times 10^6$ bits, 3-bit soft — high-statistics reference |
| RTL AWGN TB (*Tables 3b/c*) | ModelSim, RTL | $5.20 \times 10^{-3}$ | $8.00 \times 10^{-4}$ | $1.70 \times 10^{-2}$ | $9.00 \times 10^{-3}$ | $5 \times 10^3$ bits, 8-bit soft — short RTL sanity check, not a high-confidence BER estimator |
| RTL cosim (*Table 8*, *Fig. 4*) | MATLAB → ModelSim | $6.71 \times 10^{-4}$ | $8.00 \times 10^{-6}$ | $1.20 \times 10^{-2}$ | $6.90 \times 10^{-4}$ | $10^6$ bits, 8-bit soft, **final RTL** — high-statistics RTL check |

</div>

<div align="center">

*TABLE 8b: Cross-Tool BER Trend Check at Reference Operating Points*

</div>

All four flows agree on the soft-vs-hard ordering and the expected ~2 dB soft-decision advantage. The short RTL AWGN testbenches are sanity checks only; the MATLAB/Simulink references and the long RTL cosim sweep ($10^6$–$2 \times 10^6$ bits per point) are the quantitative BER evidence.

## 9. Notes and Possible Extensions

### 9.1 Limitations

- Final $F_{\max}$ (slow 85 °C): 34.01 MHz soft, 32.32 MHz hard; neither closes the 100 MHz SDC reference — it is a slack reference, not a target.
- Quartus builds are virtual-pin characterization fits with negative hold slack; not board-ready timing closure.
- Full-history survivor shifting scales poorly with constraint length.
- Soft in-cycle normalization is the dominant soft-side $F_{\max}$ ceiling (§7.2).
- RTL AWGN testbenches (§5.2) are short sanity checks; quantitative BER comes from §8.2 and §8.3.

### 9.2 Open Items

The following remain open. *Path-metric normalization* and *continuous-stream cosim* (originally listed here) are now part of the final RTL and have been moved into §4 and §8.3.

- **Break the ACS feedback loop.** With pipelining enabled, the remaining critical path on both decoders is the ACS recursion itself: `path_metric → BMU + add‐compare‐select → next_path_metric`. This is a closed loop, so it cannot be cut by adding a register without changing the algorithm. Two options: (a) re-encode the trellis to advance two symbols per cycle (radix-4 ACS), which doubles the per-cycle work but lets a register sit between BMU and add-compare-select; (b) operate the BMU on a one-cycle-stale soft input and write the metric back into `path_metric` a cycle later, which is fine for steady-state decoding but needs care at startup. Either is the next step for raising $F_{\max}$ further once the architectural-comparison goal of this project is met.
- **Cheaper soft-side normalization.** The hard decoder gets pipelined-offset normalization (parallel min reduction) almost for free in $F_{\max}$ because the unit-magnitude oscillation in the resulting recurrence is bounded by the small ($\pm 2$) branch metric. The same trick costs ~16 MHz on the soft decoder because of the ($\pm 254$) branch-metric scale, so the final soft RTL uses the in-cycle form. A two-cycle-deeper offset pipeline (or scaling the soft inputs down before ACS) might recover that without losing correctness on continuous streams.
- **Larger constraint length.** Extending to $K = 7$ multiplies the survivor memory and ACS hardware by 16 and would expose the value of survivor-memory partitioning and register-exchange traceback over the current full-history shift implementation.

## 10. References

1. Viterbi, A. J. *Convolutional Codes and Their Performance in Communication Systems*. Included in [Supporting Documentation/viterbi.pdf](Supporting%20Documentation/viterbi.pdf). Provides the original ACS recursion, trellis formulation, and asymptotic coding-gain analysis used as the algorithmic reference for both decoders in this project.
2. *Hard and Soft Decision Decoding Using the Viterbi Algorithm*. Included in [Supporting Documentation/Hard_and_Soft_Decision_Decoding_Using_Viterbi_Algorithm.pdf](Supporting%20Documentation/Hard_and_Soft_Decision_Decoding_Using_Viterbi_Algorithm.pdf). Source for the soft vs hard branch-metric formulation in *Equations 3* and *4* and the ~2 dB soft-over-hard coding-gain expectation that the MATLAB sweep in §8 confirms.
3. MathWorks. *Communications Toolbox — `poly2trellis`, `convenc`, `vitdec`*. Reference documentation for the trellis structure and `vitdec` soft/hard modes used by [Viterbi_Decoder_Project.m](coding/matlab/Viterbi_Decoder_Project.m) and the Simulink companion model.
4. Intel/Altera. *Quartus Prime Standard 25.1 Lite — Timing Closure and Optimization User Guide*. Reference for the Slow 1100 mV 85 °C $F_{\max}$ corner and slack reporting conventions used in *Table 5*.
