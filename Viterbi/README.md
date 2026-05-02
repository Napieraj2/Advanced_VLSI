# Advanced VLSI: Viterbi Decoder Project
## 1. Project Overview

This folder contains hard-decision and soft-decision Viterbi decoders for a rate-1/2, constraint-length-3 convolutional code with generator polynomials $(7, 5)_8$. Both decoders share the same trellis structure, add-compare-select (ACS) recursion, and traceback survivor memory; they differ only in the branch-metric calculation. The goal of this sub-project was to build a clean, parameterized reference implementation that could be exercised under both noisy soft-input channels and bit-flip hard-input channels, and to compare the two on a common testbench.

### 1.1 Specification
The convolutional code under test is a textbook NASA-style rate-1/2, $K = 3$ encoder. *Table 1* lists the parameters used for both decoder variants.

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

*TABLE 1: Convolutional Code and Decoder Parameters*

### 1.2 Motivation
What made this project interesting was not the encoder itself; convolutionally encoding 4-state trellises is well-trodden ground. The interesting part was reasoning about how the decoder behaves on the receive side under two very different channel models. Soft decoding gives the decoder a confidence value for each received symbol coordinate, and the branch metric is allowed to be a continuous-looking signed sum. Hard decoding throws all of that away and gives the decoder only a binary symbol, so the branch metric collapses to a Hamming distance. The same RTL skeleton handles both cases, which makes the comparison clean: the only thing that changes is the metric function. Working through that side-by-side was the most useful part of the exercise.

## 2. Repository Structure

```
Advanced_VLSI/
├── Viterbi/
│   ├── README.md
│   └── coding/
│       ├── verilog/
│       │   ├── viterbi_soft_decoder.v        ← Soft-decision decoder RTL
│       │   ├── viterbi_hard_decoder.v        ← Hard-decision decoder RTL
│       │   ├── tb_viterbi_soft_decoder.v     ← Soft-decision testbench
│       │   ├── tb_viterbi_hard_decoder.v     ← Hard-decision testbench
│       │   └── quartus/                      ← Cyclone V synthesis projects (soft + hard revisions)
│       ├── matlab/
│       │   ├── Viterbi_Decoder_Project.m     ← BER-vs-Eb/N0 sweep, soft vs hard tradeoff study
│       │   └── plots/
│       └── simulink/
│           └── Viterbi_Simulink_Model.slx    ← Block-diagram BER cross-check
├── .gitignore
└── LICENSE
```

## 3. Algorithm Background

### 3.1 Encoder
The encoder is a standard rate-1/2, $K = 3$ convolutional encoder driven by a 2-bit shift register that holds the previous two input bits. Let $u_n$ be the current input bit and $(s_1, s_0)$ be the two register bits, with $s_1$ being the older bit. The two coded output bits per input are given in *Equations 1* and *2*, matching generators $g_0 = 7_8$ and $g_1 = 5_8$.

$$c_0(n) = u_n \oplus s_1 \oplus s_0$$
(*Equation 1*)

$$c_1(n) = u_n \oplus s_0$$
(*Equation 2*)

The encoder advances by shifting $u_n$ into the register, so the next state becomes $(u_n, s_1)$. The same `enc_out` function is used in both the testbench (to generate the transmitted symbols) and inside the decoder (to compute the expected output for every trellis branch), which guarantees consistency between the two.

### 3.2 Trellis
The 2-bit register defines $2^{K-1} = 4$ states. From any state, two branches leave: one for $u_n = 0$ and one for $u_n = 1$. Two branches also enter every state, since the new state $(u_n, s_1)$ is reachable from both $(s_1, 0)$ and $(s_1, 1)$. The four-state, two-branches-per-node butterfly is the structure on which the ACS recursion runs.

### 3.3 Branch Metric
This is the only place the soft and hard decoders differ.

#### Soft Decoder
Soft inputs $r_0, r_1$ are signed values centered around zero, where positive values lean toward bit `1` and negative values lean toward bit `0`. For an expected coded pair $(e_1, e_0)$, the branch metric is the dot product in *Equation 3*. A correctly received symbol contributes a positive value; a wrong one contributes a negative value of equal magnitude. Higher path metric is better.

$$BM_{soft} = \bigl(e_1 = 1 \;?\; r_0 : -r_0\bigr) + \bigl(e_0 = 1 \;?\; r_1 : -r_1\bigr)$$
(*Equation 3*)

#### Hard Decoder
Hard inputs collapse to single bits $\hat{r}_0, \hat{r}_1$. The branch metric is a $\{+1, -1\}$ agreement count, equivalent to negative Hamming distance, as shown in *Equation 4*. Same direction as the soft case: higher is better, and the rest of the ACS pipeline can stay identical.

$$BM_{hard} = \bigl(e_1 = \hat{r}_0 \;?\; +1 : -1\bigr) + \bigl(e_0 = \hat{r}_1 \;?\; +1 : -1\bigr)$$
(*Equation 4*)

### 3.4 Add-Compare-Select
For each destination state $d$ at symbol time $n$, the ACS step takes the two incoming branches from predecessor states $p_0$ and $p_1$, adds the branch metric, and keeps the larger candidate, as shown in *Equations 5* and *6*.

$$M'(d) = \max\Bigl(M(p_0) + BM(p_0 \!\to\! d), \; M(p_1) + BM(p_1 \!\to\! d)\Bigr)$$
(*Equation 5*)

$$\mathrm{survivor}(d) = \arg\max\Bigl(M(p_0) + BM(p_0 \!\to\! d), \; M(p_1) + BM(p_1 \!\to\! d)\Bigr)$$
(*Equation 6*)

To handle the cold-start case, only state 0 is initialized to $M = 0$ and the other three states start at `METRIC_MIN = -(2^{15}-1)`. Branches whose predecessor sits at `METRIC_MIN` are skipped, so the trellis can only be entered from state 0 at $n = 0$. This avoids spurious survivors during the initial fill window.

### 3.5 Survivor Memory and Traceback
A 2-D survivor history of depth `TB_DEPTH = 12` records, for every state and every recent symbol, the predecessor state and the input bit that won the ACS at that step. Each cycle the entire history is shifted by one column, and the new ACS results are written into column 0. After the recursion, the decoder picks the state with the highest current path metric and walks backward 12 steps along its survivor pointers. The bit emitted at the deepest step is taken as the decoded output.

Twelve symbols is roughly four constraint lengths, which is the conventional rule of thumb for Viterbi traceback depth. It is deep enough that nearly all surviving paths have merged by the time the decoder commits, but shallow enough that the survivor RAM and traceback logic stay small.

## 4. Verilog Implementation

Both decoders are written as a single combinational `next_*` block plus a registered update block, which keeps the code compact and lets the same skeleton serve both metric variants. *Table 2* maps the major sections of the RTL to their algorithmic role.

| Section | Role |
|---|---|
| `enc_out` function | Branch labeling: matches encoder for trellis expansion |
| `branch_metric` function | Soft dot-product or hard agreement count |
| ACS loop over `(s, b)` | Computes candidate metrics and selects per-state survivor |
| Survivor shift loop | Shifts `survivor_prev`/`survivor_bit` history by one column |
| Best-state search | Picks max-metric state for traceback start |
| Traceback loop | Walks 12 steps back along survivor pointers |
| Sequential block | Updates path metrics, survivor RAM, output registers |

*TABLE 2: Decoder RTL Section Map*

### 4.1 Soft Decoder (`viterbi_soft_decoder.v`)
The soft decoder is parameterized by `SOFT_W` (default 8) for the input width and `METRIC_W` (default 16) for the internal path metric. With `SOFT_W = 8`, soft inputs span $[-127, +127]$. The branch metric is bounded by $\pm 2 \cdot (2^{SOFT_W-1}-1)$ per symbol, so 16-bit metrics give plenty of headroom over the traceback window without ever approaching `METRIC_MIN`. The decoded output appears one cycle after the ACS completes, with `decoded_valid` asserting once `sym_count` has reached `TB_DEPTH-1`.

### 4.2 Hard Decoder (`viterbi_hard_decoder.v`)
The hard decoder strips out the soft input ports and replaces them with two single-bit symbol pins (`rx0`, `rx1`). Branch metrics are now restricted to the set $\{-2, 0, +2\}$, so 16-bit path metrics are far wider than necessary; the width was kept identical to the soft variant for parameter symmetry. Everything else, including ACS, survivor shift, traceback, and output handshake, is identical to the soft version.

## 5. Testbench and Simulation

Both testbenches share the same skeleton, summarized in *Table 3*. The differences are isolated in the channel model and the input port set.

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

*TABLE 3: Common Simulation Conditions*

### 5.1 Soft Channel Model
Each encoded bit is mapped to a nominal soft level of $+48$ for `1` and $-48$ for `0`, then perturbed by a uniform integer noise sample on $[-6, +6]$ (centered by subtracting 6 from `|$random| % 13`). The result fits comfortably inside the 8-bit signed range and gives the soft decoder enough signal-to-noise margin to reach zero bit errors per run. The noise model is intentionally simple; it is not a true AWGN process, but it is enough to confirm that the soft branch metric is integrating evidence rather than committing on individual symbols.

### 5.2 Hard Channel Model
The hard testbench applies independent bit flips to each of the two coded coordinates with probability 8% per coordinate. Cross-coordinate flips can therefore occasionally produce a fully wrong symbol, which is the worst case for the metric. Twelve symbols of traceback at a code rate of 1/2 and constraint length 3 is enough to absorb that level of channel noise on short messages without uncorrectable errors.

### 5.3 Pass/Fail Reporting
Both testbenches register decoded bits as they arrive against the original `tx_bits` array and increment `err_count` on every mismatch. After the drain phase, the testbench prints the number of bits checked, the error count, and either `PASS` or `FAIL`.

## 6. Run Instructions

### 6.1 Icarus Verilog
From the repository root:

```bash
cd Viterbi/coding/verilog
iverilog -g2005-sv -o simv_soft tb_viterbi_soft_decoder.v viterbi_soft_decoder.v
vvp simv_soft

iverilog -g2005-sv -o simv_hard tb_viterbi_hard_decoder.v viterbi_hard_decoder.v
vvp simv_hard
```

Open the resulting waveforms with:

```bash
gtkwave tb_viterbi_soft_decoder.vcd
gtkwave tb_viterbi_hard_decoder.vcd
```

### 6.2 ModelSim / Questa
From the repository root:

```bash
cd Viterbi/coding/verilog
vlog viterbi_soft_decoder.v tb_viterbi_soft_decoder.v
vsim -c tb_viterbi_soft_decoder -do "run -all; quit -f"

vlog viterbi_hard_decoder.v tb_viterbi_hard_decoder.v
vsim -c tb_viterbi_hard_decoder -do "run -all; quit -f"
```

### 6.3 PowerShell Batch Run
To compile and run both testbenches in one shot under ModelSim:

```powershell
Set-Location "[Path to project folder]\Viterbi\coding\verilog"
$vlib = "[Path to ModelSim]\vlib.exe"
$vlog = "[Path to ModelSim]\vlog.exe"
$vsim = "[Path to ModelSim]\vsim.exe"
$tests = @('tb_viterbi_soft_decoder','tb_viterbi_hard_decoder')
if (Test-Path work) { Remove-Item -Recurse -Force work }
& $vlib work
Get-ChildItem *.v | ForEach-Object {
    & $vlog -work work $_.Name
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
foreach ($tb in $tests) {
    & $vsim -c -lib work $tb -do "run -all; quit -f"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

## 7. Synthesis

The two decoders were pushed through the same Cyclone V flow as the FIR sub-project, with one Quartus *revision* per metric variant living under [Viterbi/coding/verilog/quartus/](Viterbi/coding/verilog/quartus). The intent is timing/area characterization only — there are no pin assignments or board bring-up artifacts; everything except `clk` is declared as a virtual pin in each `.qsf`.

### 7.1 Project Setup

| Item | Value |
|---|---|
| Family / Device | Cyclone V `5CGXFC9E7F35C8` |
| Quartus version | 25.1 Lite |
| Target clock | 100 MHz (`viterbi.sdc`, identical to `fir.sdc`) |
| Revisions | `viterbi_soft` (top: `viterbi_soft_decoder`)<br>`viterbi_hard` (top: `viterbi_hard_decoder`) |
| Shared SDC | [viterbi.sdc](Viterbi/coding/verilog/quartus/viterbi.sdc) — 100 MHz clock, 5.0/0.0 ns I/O delay, false-path on `rst_n` |
| Critical-path script | [critical_path_extract.tcl](Viterbi/coding/verilog/quartus/critical_path_extract.tcl) |

*TABLE 4: Quartus Project Setup*

From the [quartus/](Viterbi/coding/verilog/quartus) folder, either revision can be compiled standalone:

```bash
quartus_sh --flow compile viterbi_soft
quartus_sh --flow compile viterbi_hard
quartus_sta -t critical_path_extract.tcl viterbi_soft
quartus_sta -t critical_path_extract.tcl viterbi_hard
```

### 7.2 Post-Fit Results

Numbers below are read directly from `output_files/<rev>.fit.summary` and the Slow 1100 mV 85 °C corner of `<rev>.sta.rpt`.

| Metric | `viterbi_soft` | `viterbi_hard` |
|---|---|---|
| ALMs (Logic utilization) | 410 / 113,560 | 346 / 113,560 |
| Total registers | 211 | 192 |
| Block memory bits | 0 | 0 |
| DSP blocks | 0 | 0 |
| Slow 85 °C $F_{\max}$ | **32.32 MHz** | **23.64 MHz** |
| Slow 85 °C setup slack @ 100 MHz | $-20.94$ ns | $-32.30$ ns |

*TABLE 5: Synthesis Results on Cyclone V `5CGXFC9E7F35C8`*

The area numbers line up with intuition: the soft decoder is ~19 % larger because its branch-metric path carries `SOFT_W = 8` signed samples through the ACS adder tree, while the hard decoder's branch metrics live in $\{-2, 0, +2\}$. Register counts move by a similar amount and trace almost entirely to the survivor RAM, which is unchanged in width between the two variants.

The $F_{\max}$ result is more interesting. Both decoders miss the 100 MHz target by a wide margin, with the *hard* variant the slower of the two. Two things drive this: the ACS for every destination state, the best-state search, and a 12-deep traceback walk all sit in a single combinational block, which produces a critical path that scales with `TB_DEPTH` rather than with metric width; and the hard decoder's narrow $\{-2, 0, +2\}$ branch metrics let synthesis fold more logic into LUT chains that ended up routing onto longer wires than the soft decoder's wider, more regular adder structure. Pipelining the ACS, the best-state search, and the traceback into separate stages would dissolve this critical path entirely — the same lever the FIR sub-project pulled to push from `fir_basic` to `fir_pipelined`. That work is captured as the first item under §9.

## 8. MATLAB Tradeoff Study

A Communications Toolbox script under [Viterbi/coding/matlab/](Viterbi/coding/matlab) re-implements the same code with `poly2trellis(3,[7 5])` and runs a BER-vs-$E_b/N_0$ sweep over an AWGN channel using `vitdec` in both `'hard'` and `'soft'` modes (3-bit soft quantization, traceback depth 12 — same as the RTL). A Simulink companion in [Viterbi/coding/simulink/](Viterbi/coding/simulink) wraps the same trellis in a block-diagram model and produces independent BER readouts as a cross-check.

Run the script (and rebuild the model) from MATLAB:

```matlab
cd Viterbi/coding/matlab
Viterbi_Decoder_Project       % BER sweep, plot, coding-gain table

cd ../simulink
build_viterbi_simulink_model  % regenerates Viterbi_Simulink_Model.slx
open_system('Viterbi_Simulink_Model')
sim('Viterbi_Simulink_Model'); disp(BER_soft); disp(BER_hard)
```

The BER sweep is shown in *Figure 1*. The soft and hard curves track the textbook prediction for this code: the soft decoder sits roughly 2 dB to the left of the hard decoder, and both sit well to the left of uncoded BPSK over the SNRs where the channel actually matters.

![BER vs Eb/N0](Viterbi/coding/matlab/plots/ber_soft_vs_hard.png)

*FIGURE 1: BER vs $E_b/N_0$ for rate-1/2, $K = 3$, $(7,5)_8$ Viterbi decoding over AWGN. Soft decoding (3-bit) gains roughly 2 dB over hard at $\mathrm{BER} = 10^{-4}$ and roughly 3 dB over uncoded BPSK.*

### 8.1 Combined Tradeoff View

Layering the synthesis numbers from §7 onto the BER results gives the picture the project was after in the first place — area/timing on one axis, channel performance on the other.

| Decoder | ALMs | Regs | $F_{\max}$ (slow 85 °C) | $E_b/N_0$ @ BER $= 10^{-4}$ | Coding gain vs uncoded |
|---|---|---|---|---|---|
| Soft (3-bit) | 410 | 211 | 32.32 MHz | $\approx 5.5$ dB | $\approx 3$ dB |
| Hard | 346 | 192 | 23.64 MHz | $\approx 7.5$ dB | $\approx 1$ dB |

*TABLE 6: Combined Hardware/Channel Tradeoff*

The takeaway is straightforward: the soft decoder costs ~19 % more ALMs and ~10 % more registers and, in this particular synthesis run, actually closes timing better than the hard decoder. In exchange it buys ~2 dB of additional coding gain at $\mathrm{BER} = 10^{-4}$, which is the full 2 dB the textbook quotes for soft over hard on this code. If the design were ever to be deployed, the soft decoder is the clear pick on both fronts; the hard decoder is interesting mainly as the smaller, simpler reference point that the soft variant is measured against.

## 9. Notes and Possible Extensions

A few directions this design could be taken further if the project were continued:

- **Pipelined ACS.** Both decoders compile to roughly 25–32 MHz $F_{\max}$ on Cyclone V because the ACS for every destination state, the best-state search, and a 12-deep traceback walk are all combinational inside a single `always @*` block. Splitting branch-metric computation, add-compare, best-state selection, and traceback into separate pipeline stages would close the 100 MHz target with margin to spare, at the cost of a few extra cycles of latency. This mirrors the FIR pipelining trade-off in the sister project and is the most impactful next step for either decoder.
- **Larger constraint length.** Extending to $K = 7$ (the standard 64-state convolutional code used in practice) would multiply the survivor memory and ACS hardware by 16 and would expose the value of survivor-memory partitioning and register-exchange traceback over the current full-history shift implementation.
- **True AWGN soft channel in the testbench.** The Verilog soft testbench uses bounded uniform noise, which is enough to confirm the metric integrates evidence but is not a true AWGN process. The MATLAB study under §8 already runs the design model over AWGN; porting an LFSR-based Box–Muller noise source into the RTL testbench would let the hardware decoder be characterized against the same BER curves end-to-end.
