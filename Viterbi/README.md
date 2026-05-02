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

### 4.3 Architectural Differences Between the Two Decoders
Both decoders share the same RTL skeleton, so it is worth being precise about what actually changes when the metric switches from soft to hard. *Table 2b* highlights the differences that surface in synthesis.

| Aspect | Soft Decoder | Hard Decoder |
|---|---|---|
| Channel inputs | `soft0`, `soft1`, each `signed [SOFT_W-1:0]` (default 8 b, range $[-127, +127]$) | `rx0`, `rx1`, each one bit |
| Branch-metric expression | $BM = (e_1 ? r_0 : -r_0) + (e_0 ? r_1 : -r_1)$ — signed dot product (*Eq. 3*) | $BM = (\pm 1) + (\pm 1)$ — agreement count, $\{-2, 0, +2\}$ (*Eq. 4*) |
| Branch-metric range per symbol | $\pm 2 \cdot (2^{SOFT_W-1}-1) = \pm 254$ | $\pm 2$ |
| Branch-metric hardware | Two `SOFT_W`-wide signed conditional negates plus a `METRIC_W`-wide adder | Two single-bit XNORs feeding $\pm 1$ constants into a small adder |
| ACS adder width driven by | `METRIC_W + log2(TB_DEPTH)` headroom over $\pm 254$ symbol metrics | Same `METRIC_W` for parameter symmetry, but only ~3 LSBs are ever non-zero |
| Path-metric dynamic range over `TB_DEPTH = 12` | $\pm 12 \cdot 254 \approx \pm 3000$ | $\pm 24$ |
| Quantization sensitivity | Decoder integrates analog confidence; clipping `SOFT_W` directly trades coding gain for area | Decoder discards confidence at the slicer; no internal knob for performance vs area |
| Best-state comparator | Compares wide signed metrics; LUT-rich, fewer carry chains needed | Compares narrow effective metrics; tool tends to pack into longer carry chains |
| What is shared | `enc_out`, ACS loop topology, `survivor_prev`/`survivor_bit` survivor RAM, traceback walk, output handshake, reset pattern | Identical |

*TABLE 2b: Soft vs Hard — Architectural Differences*

The practical consequence is that the soft decoder is the wider design but also the more regularly structured one: every branch metric is a signed sum of two signed terms, and the ACS adder tree is sized once for the worst-case soft input. The hard decoder is narrower per branch but exposes every constant to the synthesizer, which is what produces the slightly worse $F_{\max}$ result reported in §7 — the tool collapses small adders onto long carry chains that route poorly relative to the soft decoder's wider but more uniform datapath.

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

Numbers below are read directly from `output_files/<rev>.fit.summary` and the Slow 1100 mV 85 °C corner of `<rev>.sta.rpt`, after a clean full compile of both revisions on May 2, 2026 with the latch and truncation warnings cleared from the RTL. Each revision was fit twice — once with `PIPELINE = 0` (baseline, identical to the original implementation) and once with `PIPELINE = 1`. The pipelined mode is **deeper for the soft decoder than for the hard decoder**, because the two designs have very different critical paths (see commentary below):

* `viterbi_hard` pipelined: a single input-side register stage on `rx0`/`rx1`/`in_valid` ahead of the BMU. **+1** cycle of decode latency.
* `viterbi_soft` pipelined: same input-side register stage, **plus** retiming of the best-state max search and the 12-deep traceback walk so they read from the *registered* `path_metric` and `survivor_*` arrays instead of the freshly-computed `next_*` combinational network. **+2** cycles of decode latency.

The extra logic in either mode is fenced off in both decoders by clearly labeled `// === PIPELINE additions ===` blocks; with `PIPELINE = 0` the wires resolve straight to the raw inputs, the unused registers are pruned, and the traceback reads the freshly-computed `next_*` arrays — so the baseline column reproduces the original synthesis exactly.

| Metric | `viterbi_soft` (baseline) | `viterbi_soft` (pipelined) | `viterbi_hard` (baseline) | `viterbi_hard` (pipelined) |
|---|---|---|---|---|
| ALMs (Logic utilization) | 410 / 113,560 ($<$ 1 %) | 326 / 113,560 ($<$ 1 %) | 346 / 113,560 ($<$ 1 %) | 342 / 113,560 ($<$ 1 %) |
| Total registers | 211 | 231 | 192 | 193 |
| Total virtual pins | 20 | 20 | 6 | 6 |
| Block memory bits | 0 | 0 | 0 | 0 |
| RAM blocks | 0 | 0 | 0 | 0 |
| DSP blocks | 0 | 0 | 0 | 0 |
| Slow 85 °C $F_{\max}$ | **32.32 MHz** | **50.10 MHz** | **23.64 MHz** | **32.67 MHz** |
| Slow 85 °C setup slack @ 100 MHz | $-20.94$ ns | $-9.96$ ns | $-32.30$ ns | $-20.61$ ns |
| Slow 85 °C hold slack | $-10.74$ ns | $-10.26$ ns | $-10.05$ ns | $-9.95$ ns |
| Decode latency | $TB\_DEPTH$ cycles | $TB\_DEPTH + 2$ cycles | $TB\_DEPTH$ cycles | $TB\_DEPTH + 1$ cycles |
| Fitter status | Successful | Successful | Successful | Successful |

*TABLE 5: Synthesis Results on Cyclone V `5CGXFC9E7F35C8` — baseline vs pipelined (input register + traceback retiming for soft, input register only for hard)*

The area numbers line up with intuition: at baseline the soft decoder is ~19 % larger because its branch-metric path carries `SOFT_W = 8` signed samples through the ACS adder tree, while the hard decoder's branch metrics live in $\{-2, 0, +2\}$. Pipelined ALM counts actually drop on both sides, with the soft decoder dropping the most (410 → 326, −20 %): retiming the traceback to read from registered survivors lets the fitter discard the wide combinational `next_*` mux network the baseline had to build for the in-cycle traceback walk, and replace it with simpler register-fed reads. The register count climbs by ~10 % on the soft side to support the input-register stage and the now-isolated max/traceback fanout, and barely moves on the hard side (+1 register overall, since `rx0_q`/`rx1_q`/`in_valid_q` collapse into a near-trivial slice).

The $F_{\max}$ result is where the two decoders react very differently to pipelining, and it lines up with where each one's critical path actually lives.

* The **hard** decoder gains a clean +38 % from the input-side register alone (23.64 → 32.67 MHz). With the BMU collapsed to a $\pm 1$ pair, its longest combinational path was running from the input pins through channel-input routing into the ACS comparator chain, and the new register stage breaks exactly that path. A deeper retiming would not buy much more, because beyond the input cut the hard decoder's combinational cone is narrow and balanced.
* The **soft** decoder needs the deeper cut. Its critical path is *not* at the input pins but inside the closed ACS-plus-traceback combinational cone, where for every symbol the design computes `next_path_metric[]`, then immediately does a 4-way max over those values, then walks 12 steps of traceback through `next_survivor_*`. An input-side register alone slightly *hurt* the soft decoder (32.32 → 28.72 MHz in an interim fit) because it added fanout without breaking that internal cone. Once the max search and traceback are retimed to read the *registered* `path_metric`/`survivor_*` arrays, the long traceback mux chain runs in parallel from registers rather than chained off ACS results, and the critical path collapses to the ACS recursion itself. Soft $F_{\max}$ rises from 32.32 MHz to **50.10 MHz** (+55 %) at a cost of two extra cycles of latency.

Neither variant closes the 100 MHz target yet — the remaining critical path on both is now the ACS recursion's `path_metric \to BMU + add\text{-}compare\text{-}select \to next\_path\_metric` loop, which is a closed feedback path that cannot be sliced without changing the algorithm (e.g., re-encoding the trellis to operate on two symbols at a time, or breaking the BMU into its own pipelined stage with a cycle-delayed metric write-back). Those are the next options listed in §9.

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
| Soft (3-bit), baseline | 410 | 211 | 32.32 MHz | $\approx 5.5$ dB | $\approx 3$ dB |
| Soft (3-bit), pipelined | 326 | 231 | 50.10 MHz | $\approx 5.5$ dB | $\approx 3$ dB |
| Hard, baseline | 346 | 192 | 23.64 MHz | $\approx 7.5$ dB | $\approx 1$ dB |
| Hard, pipelined | 342 | 193 | 32.67 MHz | $\approx 7.5$ dB | $\approx 1$ dB |

*TABLE 6: Combined Hardware/Channel Tradeoff (baseline vs pipelined)*

The takeaway is straightforward: the soft decoder costs ~19 % more ALMs and ~10 % more registers at baseline and, in this particular synthesis run, actually closes timing better than the hard decoder. In exchange it buys ~2 dB of additional coding gain at $\mathrm{BER} = 10^{-4}$, which is the full 2 dB the textbook quotes for soft over hard on this code. If the design were ever to be deployed, the soft decoder is the clear pick on both fronts; the hard decoder is interesting mainly as the smaller, simpler reference point that the soft variant is measured against. Once pipelining is enabled, the soft decoder's advantage widens further: at $+2$ cycles of latency it reaches 50.1 MHz on 326 ALMs / 231 registers — simultaneously the fastest *and* smallest design in the table. The hard decoder, with only an input-register cut available to it, lands at 32.7 MHz / 342 ALMs. Closing 100 MHz on either variant still requires breaking the ACS recursion itself, listed under §9.

## 9. Notes and Possible Extensions

A few directions this design could be taken further if the project were continued:

- **Pipelined ACS.** Both decoders compile to roughly 25–32 MHz $F_{\max}$ on Cyclone V because the ACS for every destination state, the best-state search, and a 12-deep traceback walk are all combinational inside a single `always @*` block. Splitting branch-metric computation, add-compare, best-state selection, and traceback into separate pipeline stages would close the 100 MHz target with margin to spare, at the cost of a few extra cycles of latency. This mirrors the FIR pipelining trade-off in the sister project and is the most impactful next step for either decoder.
- **Larger constraint length.** Extending to $K = 7$ (the standard 64-state convolutional code used in practice) would multiply the survivor memory and ACS hardware by 16 and would expose the value of survivor-memory partitioning and register-exchange traceback over the current full-history shift implementation.
- **True AWGN soft channel in the testbench.** The Verilog soft testbench uses bounded uniform noise, which is enough to confirm the metric integrates evidence but is not a true AWGN process. The MATLAB study under §8 already runs the design model over AWGN; porting an LFSR-based Box–Muller noise source into the RTL testbench would let the hardware decoder be characterized against the same BER curves end-to-end.

## 10. References

1. Viterbi, A. J. *Convolutional Codes and Their Performance in Communication Systems*. Course handout, included locally as [Supporting Documentation/viterbi.pdf](Viterbi/Supporting%20Documentation/viterbi.pdf). Provides the original ACS recursion, trellis formulation, and asymptotic coding-gain analysis used as the algorithmic reference for both decoders in this project.
2. *Hard and Soft Decision Decoding Using the Viterbi Algorithm*. Course handout, included locally as [Supporting Documentation/Hard_and_Soft_Decision_Decoding_Using_Viterbi_Algorithm.pdf](Viterbi/Supporting%20Documentation/Hard_and_Soft_Decision_Decoding_Using_Viterbi_Algorithm.pdf). Source for the soft vs hard branch-metric formulation in *Equations 3* and *4* and the ~2 dB soft-over-hard coding-gain expectation that the MATLAB sweep in §8 confirms.
3. MathWorks. *Communications Toolbox — `poly2trellis`, `convenc`, `vitdec`*. Reference documentation for the trellis structure and `vitdec` soft/hard modes used by [Viterbi_Decoder_Project.m](Viterbi/coding/matlab/Viterbi_Decoder_Project.m) and the Simulink companion model.
4. Intel/Altera. *Quartus Prime Standard 25.1 Lite — Timing Closure and Optimization User Guide*. Reference for the Slow 1100 mV 85 °C $F_{\max}$ corner and slack reporting conventions used in *Table 5*.
