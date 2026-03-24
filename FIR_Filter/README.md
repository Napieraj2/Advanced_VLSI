# Advanced VLSI: FIR Filter Design Project
## 1. Project Overview

The assigned class project focused on designing an FIR filter. Using the provided MATLAB workflow, I was able to quantize the coefficients and implement an equiripple lowpass FIR filter in Verilog.

### 1.1 Specification
The project specification baseline was set at 100 taps. As we will see in the design implementation section, this starting point did not produce an optimal signal-performance result because it led to large passband dB swings.  In *Table 1* below we can see the remaining design specs as found in the *FIR_Filter/Supporting Documentation/Project.pdf*.

| Parameter | Value |
|---|---|
| Filter type | Lowpass, linear phase (Type I) |
| Number of taps | 100, increase if needed |
| Passband edge | 0.20 × Nyquist |
| Stopband edge | 0.23 × Nyquist |
| Stopband attenuation | ≥ 80 dB |
| Passband ripple*| ≤ 0.5 dB |
| Design method | Parks–McClellan (`firpm`) equiripple [1][2] |

*TABLE 1: Project Specifications*

*Not a project requirement, but ideally the ripple is small to ensure signal integrity.

### 1.2 Motivation
What made this project rewarding and kept me most engaged was not just the FIR filter itself, although seeing the digital output appear correctly in the waveforms was satisfying. The real motivation came from reasoning through where the circuit could be simplified, where area could be reduced, how the critical path could be shortened, and how the overall structure could be reorganized to push performance further. That process became the most valuable part of the project because the implementation work forced the course concepts to become concrete.

## 2. Repository Structure

```
Advanced_VLSI/
├── FIR_Filter/
│   ├── coding/
│   │   ├── verilog/
│   │   │   ├── fir_basic.v                  ← Direct-form FIR
│   │   │   ├── fir_pipelined.v              ← Pipelined adder-tree FIR
│   │   │   ├── fir_parallel_L2.v            ← L=2 parallel (polyphase) FIR
│   │   │   ├── fir_parallel_L3.v            ← L=3 parallel (polyphase) FIR
│   │   │   ├── fir_parallel_L3_pipelined.v  ← L=3 parallel + pipelined adder trees
│   │   │   ├── fir_mcm.v                    ← MCM (CSD shift-add) direct-form FIR
│   │   │   ├── fir_mcm_pipelined.v          ← MCM + pipelined adder tree
│   │   │   ├── tb_fir*.v                    ← Testbenches (one per architecture)
│   │   │   └── quartus/                     ← Quartus project files, SDC, STA scripts
│   │   └── matlab/
│   │       ├── FIR_Filter_Project.m         ← MATLAB design + quantization script
│   │       └── plots/                       ← Exported MATLAB figures
│   ├── Supporting_Documentation/
│   │   └── Project.pdf
│   └── README.md
├── .gitignore
└── LICENSE
```

## 3. MATLAB Filter Design

### 3.1 Floating-Point Design
The filter was designed in firpm [2] using auto-tuned tap count and weighting, with normalized band edges of [0, 0.20, 0.23, 1]. The final design used 192 taps (order 191) with a stopband weight of 313.7. This configuration provided enough design freedom to meet the attenuation target after quantization, whereas the lower-tap starting point did not.

### 3.2 Coefficient Quantization
To determine the minimum usable coefficient precision, I ran a word-length sweep from 𝑄=14 to 24 bits and checked which cases still preserved at least 80 dB of stopband attenuation after rounding. The first setting that met the requirement was 𝑄=20, giving 21-bit signed coefficients. I then overlaid the floating-point and quantized magnitude responses to confirm that the quantized filter still tracked the intended design closely.

![Quantization Sweep](coding/matlab/plots/quantization_sweep.png)

#### Quantization Sensitivity and Coefficient Weights
The firpm design [2] is very effective at generating the required coefficients with relatively little manual calculation. However, it also produces a wide coefficient spread. At one end, the coefficients are as small as 153, while near the middle they reach 216,278. Quantization does not account for that spread. One LSB is still one LSB, so the smaller coefficients experience a much larger relative error. A one-step rounding error on h(0) is significant, while the same one-step error on ℎ(95) is almost negligible. Unfortunately, the coefficients affected first are often the ones contributing to the more delicate behavior near the transition edge and the stopband nulls.

The Q-sweep makes this clear quickly. At Q=16, the design is not sufficient, with the stopband attenuation falling to about 72 dB. At Q=18, performance improves to roughly 78 dB, but it still misses the target. Q=20 is the first point at which the quantized design exceeds the 80 dB requirement, reaching 80.13 dB. That is where the design was finalized. The choice of 192 taps was not immediate. I began with 100 taps because that was the baseline allowed by the specification, with the option to increase the count if necessary. It was necessary. A 0.20𝜋 to 0.23π transition band combined with an 80 dB stopband target did not leave enough design margin at 100 taps, so I built a MATLAB sweep to identify a more suitable configuration. At 192 taps, the optimizer had more freedom, the stopband weight dropped to 313.7, and the quantized coefficients became much more manageable. Of course, that created a different problem: more hardware. More taps mean more multipliers, more delay storage, and a longer summation path. That is where the structural optimizations became important.

Symmetric pre-adds halve the multiplier count, reducing it from 192 to 96. Polyphase decomposition with 𝐿=2 and 𝐿=3 splits the filter into smaller subfilters of 96 and 64 taps, shortening each channel’s adder tree. Pipelined adder trees break the 7-level combinational tree into registered stages with one adder per stage, which pushes 𝐹𝑚𝑎𝑥 much higher. MCM with CSD replaces DSP multipliers with shift-add networks. This avoids hard macros, but increases ALM routing cost.

The same trade-off appeared repeatedly throughout the project. When I tried to make the arithmetic cleaner, the structure usually became heavier. When I tried to simplify the hardware, something else became harder. Much of the learning in this project came from working through that back-and-forth process rather than expecting a single obvious solution.

### 3.3 Filter Response
![Filter Response](coding/matlab/plots/filter_response.png)
Table 2 summarizes the final floating-point and quantized filter-response metrics.

| Metric | Float | Quantized (Q=20) |
|---|---|---|
| Stopband attenuation | 80.61 dB | 80.13 dB |
| Passband ripple | 0.50 dB | 0.50 dB |

*TABLE 2: Floating-Point vs. Quantized Filter Response*

### 3.4 Accumulator Overflow Analysis
A 16-bit signed input multiplied by a 21-bit signed coefficient yields a 37-bit signed product. In the worst case, accumulation reaches 74,676,844,942, which requires a 38-bit internal accumulator to prevent overflow and preserve numerical correctness through the linear-phase computation.  Since most system interfaces use standard fixed word sizes, two options were considered: either widening the external output to 64 bits, which would waste a significant portion of the available range, or keeping a 32-bit signed output and saturating the final result.  This approach preserves safe internal arithmetic while maintaining compatibility with a narrower system interface. The main hardware cost is unchanged, because the 38-bit value must still propagate through the adder tree internally. The only difference is at the output boundary, where the result is saturated to 32 bits instead of exporting the full internal width.

## 4. Verilog Implementation
I kept the ModelSim flow the same for all seven architectures. That made comparison much easier. Every testbench has two phases so I can check both the impulse-response sequence and the steady-state DC behavior. *Table 3* lists the common simulation conditions used across all architectures. Loop iterations scale by architecture to allow complete output flushing, as summarized in *Table 4*. Multi-channel designs (L=2, L=3) feed de-interleaved inputs: the impulse goes into channel 0 only (`din_0 = 1`, others zero), and the step drives all channels equally (`din_k = 1000`). Output verification checks that the interleaved coefficient sequence across channels reconstructs the original 192-tap impulse response exactly.

| Parameter | Value |
|---|---|
| Clock | 100 MHz (10 ns period) |
| Reset | `rst_n` held low for 50 ns, released with 20 ns settling |
| Phase 1 (Impulse) | Single-sample pulse (`din = 1`) for one clock, then zero. Captures the full 192-coefficient impulse response. |
| Phase 2 (Step) | Constant `din = 1000` sustained for the full filter depth. Verifies DC-gain convergence to `sum(coeff) × 1000 = 1,018,790,000`. |
| VCD dump | Enabled for all designs; waveforms saved under `coding/verilog/` |

*TABLE 3: Common Simulation Conditions*

| Design class | Impulse cycles | Step cycles | Why |
|---|---|---|---|
| Non-pipelined, single-channel | `NUM_TAPS + 10` | `NUM_TAPS + 20` | 192 taps + margin |
| Pipelined, single-channel | `NUM_TAPS + 20` | `NUM_TAPS + 30` | extra 10 for 8-stage pipeline flush |
| L=2 parallel (non-pipelined) | `NUM_TAPS/2 + 10` | `NUM_TAPS/2 + 20` | 2 samples/clock, half the clocks |
| L=3 parallel (non-pipelined) | `NUM_TAPS/3 + 10` | `NUM_TAPS/3 + 20` | 3 samples/clock, one-third the clocks |
| L=3 parallel + pipelined | `NUM_TAPS/3 + 20` | `NUM_TAPS/3 + 30` | parallel scaling + pipeline flush |

*TABLE 4: Testbench Loop Counts by Architecture*

To compile all variants quickly in a shell environment:

Quartus:

```powershell
Set-Location "[Path to project folder]\coding\verilog\quartus"
$quartus = "[Path to quartus shell]\quartus_sh.exe"
$revisions = @('fir_basic','fir_pipelined','fir_parallel_L2','fir_parallel_L3','fir_parallel_L3_pipelined','fir_mcm','fir_mcm_pipelined')
foreach ($rev in $revisions) {
	& $quartus --flow compile $rev
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

ModelSim:

```powershell
Set-Location "[Path to project folder]\coding\verilog"
$vlib = "[Path to ModelSim]\vlib.exe"
$vlog = "[Path to ModelSim]\vlog.exe"
$vsim = "[Path to ModelSim]\vsim.exe"
$tests = @('tb_fir','tb_fir_pipelined','tb_fir_parallel_L2','tb_fir_parallel_L3','tb_fir_parallel_L3_pipelined','tb_fir_mcm','tb_fir_mcm_pipelined')
if (Test-Path work_verilog) { Remove-Item -Recurse -Force work_verilog }
& $vlib work_verilog
Get-ChildItem *.v | ForEach-Object {
	& $vlog -work work_verilog $_.Name
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
foreach ($tb in $tests) {
	& $vsim -c -lib work_verilog $tb -do "run -all; quit -f"
	if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
```

### 4.1 Direct-Form FIR (`fir_basic.v`)
The baseline implementation is the standard FIR realization shown in *Equation 1*. A direct 192-tap implementation would require 192 multipliers, which is costly. However, linear-phase symmetry allows the delay line to be folded into pre-add pairs, as shown in *Equation 2* [3]. The resulting structure uses 96 pre-adders, 96 multipliers, and a single combinational adder tree to reduce the products to one final sum.  Simulation results were consistent with the expected behavior. The 192-sample impulse response matched the designed coefficient set, the symmetric coefficient pairs aligned correctly, and the step response settled to 1,018,790,000, which is equal to `sum(coeff) × 1000`. This corresponds to a DC gain of approximately 0.972, or about −0.25 dB, which remains safely within the 0.5 dB passband limit.

$$y(n) = \sum_{k=0}^{N-1} h(k) \cdot x(n-k)$$
(*Equation 1*)

$$y(n) = \sum_{k=0}^{95} h(k) \,\bigl[\,x(n-k) + x(n-(191-k))\,\bigr]$$
(*Equation 2*)

### 4.2 Pipelined FIR (`fir_pipelined.v`)
The front-end structure is unchanged from `fir_basic`. The only modification is in the reduction path for the 96 products. In `fir_basic`, all 96 products are reduced through a single combinational adder tree that is 7 levels deep and padded to 128 entries. This approach works, but it requires the entire tree to settle within a single clock period. The pipelined version [3] instead inserts a register after every tree level, so each stage contains only a single two-input addition, as shown in *Equations 3* and *4*. After 7 adder stages, \(s_7(0)\) produces the final sum. Including the product register, this adds a total latency of 8 cycles. In exchange, timing closure becomes much easier while throughput remains at 1 sample per clock. Functionally, this architecture does not change the filter output. The impulse and step responses are bit-identical to those of `fir_basic`; they simply appear later in time. Accordingly, `dout_valid` shifts from 85 ns to 165 ns, while the coefficient sequence itself remains unchanged.

$$s_0(i) = \mathtt{product}(i), \qquad 0 \le i < 96$$

$$s_0(i) = 0, \qquad 96 \le i < 128$$
(*Equation 3*)

$$s_{m+1}(i) = reg[s_m(2i) + s_m(2i{+}1)], \qquad m = 0, \ldots, 6$$
(*Equation 4*)

### 4.3 L=2 Parallel FIR (`fir_parallel_L2.v`)
#### Polyphase Decomposition
Decompose the transfer function into even and odd polyphase components in *Equation 5*[3] where each sub-filter has $N/2 = 96$ taps in *Equation 6*. The two output samples per clock cycle are calculated in *Equations 7* and *8*, where $x_0(n) = x(2n)$ (even input stream) and $x_1(n) = x(2n{+}1)$ (odd input stream).

$$H(z) = H_e(z^2) + z^{-1}\,H_o(z^2)$$
(*Equation 5*)

$$H_e(z) = \sum_{j=0}^{95} h(2j)\,z^{-j}, \qquad H_o(z) = \sum_{j=0}^{95} h(2j{+}1)\,z^{-j}$$
(*Equation 6*)

##### *Polyphase Equations*
$$y(2n)   = \sum_{j=0}^{95} h_e(j)\,x_0(n{-}j) \;+\; \sum_{j=0}^{95} h_o(j)\,x_1(n{-}1{-}j)$$
(*Equation 7*)

$$y(2n{+}1) = \sum_{j=0}^{95} h_e(j)\,x_1(n{-}j) \;+\; \sum_{j=0}^{95} h_o(j)\,x_0(n{-}j)$$
(*Equation 8*)

##### *Symmetry-Based Multiplier Reduction*
From the original linear-phase symmetry $h(k) = h(191{-}k)$ we can see in *Equation 9*, $H_o$ is $H_e$ time-reversed. Substituting $h_o(j) = h_e(95{-}j)$ and re-indexing the odd sums lets us form cross pre-adds that share the same coefficient sets in *Equations 10* and *11*.  That takes the multiplier count from a naive 384 down to 192. So the L=2 version really does buy two outputs per clock without paying the full brute-force duplication cost.  Latency-wise, L=2 still looks like the basic design because there is only one output register stage. The gain is throughput. Two samples come out each clock, so the simulation finishes much sooner and the VCD shrinks because the same 192 outputs flush in fewer cycles.

$$h_e(j) = h(2j), \qquad h_o(j) = h(2j{+}1) = h(191{-}(2j{+}1)) = h(2(95{-}j)) = h_e(95{-}j)$$
(*Equation 9*)

$$y(2n)   = \sum_{j=0}^{95} h_e(j)\,\bigl[\,x_0(n{-}j) + x_1(n{-}96{+}j)\,\bigr]$$
(*Equation 10*)

$$y(2n{+}1) = \sum_{j=0}^{95} h_e(j)\,\bigl[\,x_1(n{-}j) + x_0(n{-}95{+}j)\,\bigr]$$
(*Equation 11*)

### 4.4 L=3 Parallel FIR (`fir_parallel_L3.v`)
#### Polyphase Decomposition (L = 3)
Decompose $H(z)$ into three polyphase branches [3] seen in *Equation 12*, where each sub-filter has $\lceil N/3 \rceil = 64$ taps as seen in *Equation 13*.  The three output samples per clock cycle are computed as seen in *Equation 14*, writing it out explicitly with $x_0(n) = x(3n)$, $x_1(n) = x(3n{+}1)$, $x_2(n) = x(3n{+}2)$ we obtain the polyphase *Equations 15, 16* and *17*, where $*$ denotes convolution with the respective polyphase sub-filter.

$$H(z) = H_0(z^3) + z^{-1}\,H_1(z^3) + z^{-2}\,H_2(z^3)$$
(*Equation 12*)

$$H_p(z) = \sum_{j=0}^{63} h(3j{+}p)\,z^{-j}, \qquad p = 0, 1, 2$$
(*Equation 13*)

$$y(3n{+}r) = \sum_{p=0}^{2} \sum_{j=0}^{63} h_p(j)\,x_{(r-p)\bmod 3}\!\left(n - j - \left\lfloor \frac{p + 2 - r}{3} \right\rfloor\right), \qquad r = 0, 1, 2$$
(*Equation 14*)

##### *Polyphase Equations*
$$y(3n)     = H_0 * x_0(n) \;+\; H_1 * x_2(n{-}1) \;+\; H_2 * x_1(n{-}1)$$
(*Equation 15*)

$$y(3n{+}1) = H_0 * x_1(n) \;+\; H_1 * x_0(n)     \;+\; H_2 * x_2(n{-}1)$$
(*Equation 16*)

$$y(3n{+}2) = H_0 * x_2(n) \;+\; H_1 * x_1(n)     \;+\; H_2 * x_0(n)$$
(*Equation 17*)

##### *Multiplier Count*
Naive \(L = 3\) polyphase decomposition requires \(3 \times 3 = 9\) sub-filter convolutions, each with 64 taps, for a total of **576 multipliers**. Two symmetry properties reduce this requirement by 50%. The first reduction comes from the \(H_0/H_2\) cross pre-add relationship derived from the overall coefficient symmetry \(h(k) = h(191-k)\), as shown in *Equation 18*. Under this symmetry, \(H_2\) is the time-reversed version of \(H_0\). By substitution and re-indexing, each \(H_0 + H_2\) pair collapses into a single cross pre-add structure, as shown in polyphase *Equations 19–21*. This means each output requires only **64 multipliers** for the \(h_0\) branch, giving a total of \(3 \times 64 = 192\).

An additional reduction comes from the self-symmetry of \(H_1\), shown in *Equation 22*. Since \(H_1\) is itself symmetric over 64 taps, it can be folded into 32 pre-add pairs as shown in *Equation 23*. As a result, each output requires only **32 multipliers** for the \(h_1\) branch, giving a total of \(3 \times 32 = 96\). The final multiplier count is therefore \(192 + 96 = 288\), which is exactly 50% of the naive 576-multiplier implementation.

Simulation confirmed correct operation across all three output channels. The impulse response reconstructs the original coefficient sequence in 3-way interleaved order, and the step response settles to 1,018,790,000 on every output. This architecture still has a one-cycle output latency like `fir_basic`, but because it produces three samples per clock, the impulse response flushes much faster and the resulting VCD is the smallest among the non-pipelined implementations.

$$h_0(j) = h(3j), \qquad h_2(j) = h(3j{+}2) = h(191{-}(3j{+}2)) = h(3(63{-}j)) = h_0(63{-}j)$$
(*Equation 18*)

##### *Polyphase Equations*
$$y(3n) = \sum_{j=0}^{63} h_0(j)\bigl[\mathtt{dl0}[j] + \mathtt{dl1}[63{-}j]\bigr] + (H_1 \text{ term})$$
(*Equation 19*)

$$y(3n{+}1) = \sum_{j=0}^{63} h_0(j)\bigl[\mathtt{dl1}[j] + \mathtt{dl2}[63{-}j]\bigr] + (H_1 \text{ term})$$
(*Equation 20*)

$$y(3n{+}2) = \sum_{j=0}^{63} h_0(j)\bigl[\mathtt{dl2}[j] + \mathtt{dl0}[63{-}j]\bigr] + (H_1 \text{ term})$$
(*Equation 21*)

##### *Pre-add pairs*
$$h_1(j) = h(3j{+}1) = h(191{-}(3j{+}1)) = h(3(63{-}j){+}1) = h_1(63{-}j)$$
(*Equation 22*)

$$\sum_{j=0}^{63} h_1(j)\,u(j) = \sum_{j=0}^{31} h_1(j)\bigl[u(j) + u(63{-}j)\bigr]$$
(*Equation 23*)

### 4.5 L=3 Parallel + Pipelined FIR (`fir_parallel_L3_pipelined.v`)
This one is just the L=3 structure with the long per-channel reduction tree broken into pipeline stages. The pre-adds, symmetry reuse, and multiplier sharing all stay the same [3].

#### Pipeline Structure

Each output channel sums 96 products, with 64 contributions from $H_0$ and 32 from $H_1$. To keep the reduction tree balanced, those 96 values are padded to $2^7 = 128$ entries before the summation begins. The first stage is therefore a padded product vector $s_0[k]$, and each later stage halves the number of entries by adding adjacent pairs. A pipeline register is inserted after every tree level. In *Equations 24-26*, $|s_m|$ denotes the number of entries present in stage $m$, not the bit width of each entry. After the seventh reduction stage, each channel is left with a single value $s_7$. *Table 5* makes the pipeline cost explicit: most of the added state is concentrated in the front half of the tree, where the padded product arrays are widest.

$$s_0[k] = \mathtt{product}[k], \qquad 0 \le k < 96$$
(*Equation 24*)

$$s_0[k] = 0, \qquad 96 \le k < 128$$
(*Equation 25*)

$$s_{m+1}[k] = s_m[2k] + s_m[2k{+}1], \qquad |s_{m+1}| = \tfrac{1}{2}|s_m|, \qquad m = 0, 1, \ldots, 6$$
(*Equation 26*)

| Stage | Entries per channel | Total registers (3 ch.) |
|---|---|---|
| s0 (product reg) | 128 | 384 |
| s1 | 64 | 192 |
| s2 | 32 | 96 |
| s3 | 16 | 48 |
| s4 | 8 | 24 |
| s5 | 4 | 12 |
| s6 | 2 | 6 |
| s7 | 1 | 3 |
| Total | | 765 |

*TABLE 5: L=3 Pipelined Adder-Tree Register Counts*

#### Latency
The latency follows directly from the register placement. There is one register stage at the product input and seven more across the reduction tree, so the pipelined structure adds 8 cycles relative to the combinational version. Including the final output register, the total `din_valid` to `dout_valid` latency becomes 9 clock cycles, as summarized in *Equations 27* and *28*.

$$L_{pipe} = 1 + 7 = 8$$
(*Equation 27*)

$$L_{total} = 1 + 7 + 1 = 9$$
(*Equation 28*)

#### Performance Summary
Table 6 compares the non-pipelined and pipelined \(L = 3\) architectures at the structural level. The interface is unchanged from `fir_parallel_L3`: the design accepts three input samples per clock (`din_0`, `din_1`, `din_2`) and produces three output samples per clock (`dout_0`, `dout_1`, `dout_2`). The `dout_valid` signal is generated by an 8-bit shift register that delays `din_valid` through the pipeline so that output validity remains aligned with the corresponding filtered results. Functionally, the outputs still match `fir_parallel_L3` bit-for-bit. The difference is in latency and bookkeeping rather than numerical behavior.

| Metric | fir\_parallel\_L3 | fir\_parallel\_L3\_pipelined |
|---|---|---|
| Multipliers | 288 | 288 |
| Adder-tree depth | 96-input combinational | 7-stage registered |
| Pipeline latency | 1 cycle | 9 cycles (+8) |
| Throughput | 3 samples/clock | 3 samples/clock |
| Critical path | Pre-add → multiply → 96-product combinational adder tree | Pre-add → multiply → 2-input add (1 stage) |

*TABLE 6: L=3 Parallel vs. L=3 Parallel Pipelined Comparison*
#### Why Pipelined Parallel Wins on Real Hardware
If I only looked at simulation time, I could talk myself into preferring the non-pipelined L3. That would be the wrong conclusion. Both testbenches run at the same fixed 100 MHz clock, so simulation hides the real issue. On hardware, Fmax matters more than how fast a testbench transcript scrolls by, and the pipelined tree wins there for obvious reasons.

### 4.6 MCM Direct-Form FIR (`fir_mcm.v`)
This is the version where I give the DSP blocks back and pay for it in logic instead. Every multiplier in `fir_basic` becomes a Canonic Signed Digit shift-add network [3].

#### CSD Decomposition
CSD uses digits in $\{-1, 0, +1\}$ and avoids adjacent non-zero entries. In hardware terms, that matters because every non-zero digit turns into extra work. The shifts are cheap. The adds and subtracts are not.

The decomposition was generated and verified in MATLAB (`FIR_Filter_Project.m`, Section 9). Table 7 summarizes the overall CSD workload:
| Metric | Value |
|---|---|
| Coefficients decomposed | 96 (symmetric half) |
| Total non-zero CSD digits | 453 |
| Average NZD per coefficient | 4.7 |
| Shift-add operations | 357 (NZD − 96) |
| DSP blocks used | **0** |

*TABLE 7: CSD Decomposition Summary*

#### Example Decompositions
Table 8 gives representative coefficient decompositions, from simple low-NZD cases to the most expensive coefficient in the set.

| Coeff | Value | CSD | NZD | Verilog Expression |
|---|---|---|---|---|
| h(0) | 153 | $+2^0 - 2^3 + 2^5 + 2^7$ | 4 | `pa<<<0 - pa<<<3 + pa<<<5 + pa<<<7` |
| h(6) | 136 | $+2^3 + 2^7$ | 2 | `pa<<<3 + pa<<<7` |
| h(19) | −240 | $+2^4 - 2^8$ | 2 | `pa<<<4 - pa<<<8` |
| h(95) | 216278 | $-2^1 - 2^3 - 2^5 + 2^8 - 2^{10} + 2^{12} + 2^{14} - 2^{16} + 2^{18}$ | 9 | 8 ops (most complex) |

*TABLE 8: Example CSD Coefficient Decompositions*

#### Architecture
Everything is identical to `fir_basic` except the multiply stage:

1. Delay line: 192-tap shift register (same as basic)
2. Symmetric pre-adds: 96 adders folding `tap[k] + tap[191-k]` (same)
3. Products: CSD shift-add networks instead of DSP multipliers. Each `preadd[k]` is sign-extended to the 38-bit internal accumulator width, then shifted and added/subtracted per the CSD decomposition.
4. Adder tree: 7-level binary tree, pad-to-128 (same)
5. Output register: 1-cycle latency (same)

#### Common Sub-Expression Analysis
MATLAB Section 9b identifies sub-expression pairs shared across multiple coefficients. The most common patterns are listed in *Table 9*. If I kept pushing this architecture, that is where I would go next. A graph-based CSE tool such as RAG-n or Hcub [3] could reuse those repeated pieces instead of rebuilding them over and over inside each coefficient network.

| Sub-expression | Occurrences across 96 coefficients |
|---|---|
| $(x \ll a) - (x \ll a{+}2)$ | 97 |
| $(x \ll a) + (x \ll a{+}2)$ | 93 |
| $(x \ll a) - (x \ll a{+}4)$ | 59 |
| $(x \ll a) + (x \ll a{+}4)$ | 56 |

*TABLE 9: Common CSD Sub-Expression Patterns*

#### Simulation and Trade-offs
Impulse and step both match `fir_basic` exactly (same 192 coefficients, same DC gain). The downside is pretty obvious in the synthesis results. Giving up 96 DSP blocks means taking on 357 add/sub operations plus a lot of extra routing, and that is why the ALM count jumps so much. The longest CSD paths are also deeper than a single DSP multiply, so timing drops from 38.7 MHz to 33.2 MHz. So where would I actually use this? Mostly in a design where DSP blocks are tight or already reserved for something else. On this Cyclone V it is mainly a comparison point. On a smaller part, it could be the practical answer.

### 4.7 MCM Pipelined FIR (`fir_mcm_pipelined.v`)
Same CSD shift-add products as `fir_mcm`, but with the 7-stage registered adder tree from `fir_pipelined` instead of a single combinational pass. Eight extra clock cycles of latency, same as the DSP pipelined variant. What surprised me a bit here is how well pipelining rescues the MCM version. Once the long CSD chains are cut up by registers, it reaches about 58.6 MHz, essentially the same as the DSP-pipelined design, and it still uses zero DSP blocks.

## 5. Synthesis Results

### 5.1 FPGA Target
Device: Cyclone V 5CGXFC9E7F35C8 (GX variant, F35 package, speed grade C8). Since this project was sythesis only the target device was picked as a potential candidate based on previous work, and number of resources available for more complex architectures.

| Resource      | Available |
|---------------|-----------|
| ALMs          | 113,560   |
| DSP blocks    | 342       |
| RAM blocks    | 1,220     |
| I/O pins      | 616       |

*TABLE 10: Cyclone V Target Device Resources*

### 5.2 DSP Chain Note
For the non-pipelined versions, explicit combinational reduction trees were necessary. If left alone, Quartus tried to infer DSP accumulation chains longer than the Cyclone V limit of 22 blocks. That path went nowhere.

### 5.3 38-Bit Internal Accumulator Results
*Table 11* collects the main post-fit area and timing results for all seven FIR architectures. \(F_{\max}\) was calculated from the worst-case setup slack \(s\), in ns, using *Equation 29* under the Slow 1100 mV, 85 \(^\circ\)C timing model, which represents the worst-case operating corner.

For the direct-form architecture, the setup slack was \(-15.832\) ns, giving \(F_{\max} = 1000 / 25.832 = 38.7\) MHz.  
For the pipelined architecture, the setup slack improved to \(-7.038\) ns, giving \(F_{\max} = 1000 / 17.038 = 58.7\) MHz.  
For the MCM direct-form architecture, the setup slack was \(-20.093\) ns, which gives \(F_{\max} = 1000 / 30.093 = 33.2\) MHz.  
For the pipelined MCM architecture, the setup slack was \(-7.074\) ns, giving \(F_{\max} = 1000 / 17.074 = 58.6\) MHz.  
For the \(L=2\) parallel architecture, the setup slack was \(-16.984\) ns, giving \(F_{\max} = 1000 / 26.984 = 37.1\) MHz. Since this version produces two output samples per clock, its throughput is \(2 \times 37.1 = 74.1\) Msps.  
For the \(L=3\) parallel architecture, the setup slack was \(-17.465\) ns, giving \(F_{\max} = 1000 / 27.465 = 36.4\) MHz. Because it produces three output samples per clock, its throughput is \(3 \times 36.4 = 109.2\) Msps.  
For the pipelined \(L=3\) architecture, the setup slack was \(-7.166\) ns, giving \(F_{\max} = 1000 / 17.166 = 58.3\) MHz. With three output samples per clock, its throughput is \(3 \times 58.3 = 174.8\) Msps.

| Architecture | Area (ALMs) | Registers | DSP Blocks | Fmax (MHz) | Throughput (Msps) |
|---|---|---|---|---|---|
| Direct-form | 1,125 | 3,731 | 96 | 38.7 | 38.7 |
| Pipelined | 3,042 | 9,313 | 96 | 58.7 | 58.7 |
| L=2 parallel | 1,696 | 3,659 | 192 | 37.1 | 74.1 |
| L=3 parallel | 2,499 | 3,719 | 288 | 36.4 | 109.2 |
| L=3 parallel + pipeline | 7,589 | 19,887 | 288 | 58.3 | 174.8 |
| MCM direct-form | 5,033 | 3,464 | 0 | 33.2 | 33.2 |
| MCM pipelined | 5,651 | 10,530 | 0 | 58.6 | 58.6 |

*TABLE 11: Post-Fit Area and Timing Results*

$$F_{\max} = \frac{1000}{10 - s}$$
(*Equation 29*)

### 5.4 Interconnect Usage
Routing resource utilization from the Quartus Fitter, reported as average and peak interconnect congestion, is summarized in *Table 12*. The routing results are more important here than the surrounding prose. The \(L=3\) parallel design shows the worst interconnect demand by a wide margin, with 12.0% average congestion and a 62.2% peak in the vertical routing direction. This is still about 1.8× the average interconnect usage of the \(L=2\) case. Structurally, three input data buses feeding 288 DSP blocks place heavy demand on the vertical routing channels between DSP columns.

The \(L=2\) parallel design is lower at 6.5% average interconnect congestion and 47.1% peak vertical congestion. This is consistent with the architecture: doubling the data paths roughly doubles the wiring burden relative to the single-stream baseline. Adding pipelining to the \(L=3\) architecture still improves routing substantially. Peak vertical congestion drops from 62.2% to 33.3%, while average interconnect usage falls from 12.0% to 8.9%. The added pipeline registers give the fitter more freedom to distribute logic across the device. The tradeoff is a large increase in register activity, with nearly 20k registers contributing 6% block interconnect usage and a maximum fan-out of 20,319. The MCM direct-form design still shows relatively high peak congestion at 31.5% despite a low average value, indicating that the CSD shift-add structures create localized routing hotspots around the large-coefficient products. The pipelined MCM version reduces that peak to 20.5% by breaking up the longer combinational paths.

Among the current runs, the DSP-pipelined design shows the lowest peak congestion at 16.5%, which is likely due to the benefit of dedicated routing within the DSP columns. This became especially clear in the \(L=3\) parallel case. I initially spent a long time focused only on the timing reports, but the real issue did not fully make sense until I examined the interconnect report. Once the routing data was included, it became clear that the vertical routing channels were the dominant bottleneck.

| Architecture | Avg Interconnect (total/H/V) | Peak Interconnect (total/H/V) | Block IC | Fan-out (avg) | Fan-out (max) |
|---|---|---|---|---|---|
| Direct-form | 2.1% / 1.7% / 3.5% | 22.9% / 19.6% / 35.1% | 8,861 (1%) | 3.86 | 3,827 |
| Pipelined | 2.1% / 1.9% / 2.6% | 16.5% / 15.1% / 20.7% | 15,072 (2%) | 3.09 | 9,457 |
| L=2 parallel | 6.5% / 5.5% / 9.7% | 32.8% / 29.6% / 47.1% | 15,785 (2%) | 4.20 | 3,851 |
| L=3 parallel | 12.0% / 9.9% / 18.9% | 39.6% / 36.6% / 62.2% | 22,537 (3%) | 4.48 | 4,007 |
| L=3 parallel + pipeline | 8.9% / 7.6% / 13.1% | 20.9% / 18.4% / 33.3% | 41,703 (6%) | 3.00 | 20,319 |
| MCM direct-form | 2.1% / 2.1% / 2.2% | 31.5% / 30.7% / 34.1% | 19,381 (3%) | 3.14 | 3,464 |
| MCM pipelined | 2.0% / 2.0% / 1.9% | 20.5% / 21.4% / 17.8% | 21,255 (3%) | 2.99 | 10,530 |

*TABLE 12: Interconnect Congestion and Fan-Out Summary*

### 5.5 Critical Path Delay Breakdown
The earlier CELL-versus-IC breakdown table was generated from a separate manual `report_timing -detail full_path` run. Because that custom timing report was not regenerated during the current standardized Quartus rerun, I removed the stale table rather than keep values that no longer matched the rest of the section. The source-of-truth tables presented here now come directly from the latest `.fit.summary`, `.sta.summary`, `.fit.rpt`, and `.pow.summary` files.

### 5.6 Power Estimation
These numbers were obtained from Quartus Prime PowerPlay using vectorless estimation with the default 12.5% toggle rate, so they were treated as comparative ranking data rather than absolute power values. *Table 13* summarizes these estimates. Static power changes very little across the different architectures, so the more meaningful differences appear in dynamic power.

The clearest trend is that the MCM-based implementations consume significantly less dynamic power than the DSP-heavy versions, which is consistent with their reduced dependence on dedicated multiplier hardware. At the other extreme, the pipelined \(L=3\) architecture is the most expensive in power by a wide margin. This is not difficult to explain structurally: it combines three parallel channels, deeply registered adder trees, and a 100 MHz operating target. More broadly, the same pattern appears across the design set: whenever timing improves through the addition of more pipeline registers, the power cost tends to increase in return.

One important caveat is that these are not activity-driven power estimates. They are useful for comparing the relative behavior of the seven architectures, but they should not be treated as final sign-off power numbers.

| Architecture | Dynamic (mW) | Static (mW) | I/O (mW) | Total (mW) |
|---|---|---|---|---|
| Direct-form | 39.0 | 519.1 | 6.7 | 564.8 |
| Pipelined | 100.5 | 519.9 | 6.7 | 627.1 |
| L=2 parallel | 73.3 | 519.5 | 6.7 | 599.6 |
| L=3 parallel | 105.7 | 520.0 | 6.7 | 632.3 |
| L=3 parallel + pipeline | 343.9 | 523.1 | 6.7 | 873.7 |
| MCM direct-form | 17.9 | 518.8 | 6.7 | 543.4 |
| MCM pipelined | 30.7 | 519.0 | 6.7 | 556.4 |

*TABLE 13: Vectorless Power Estimation Summary*

## 6. Further Analysis and Conclusion

### 6.1 Architecture Comparison
Putting all of the architectures on the same throughput-efficiency basis makes the trade-offs much easier to compare. *Table 14* compiles the derived efficiency metrics using the 38-bit internal accumulator results. The clearest result from the table is straightforward: once the filter reaches this size, pipelining is no longer optional. Whether the implementation uses DSP blocks, MCM, or polyphase parallelism, the same pattern appears. The pipelined versions cluster tightly between about 58.3 and 58.7 MHz, while the non-pipelined versions remain limited to the low-to-high 30 MHz range because the reduction tree dominates the critical path.

Polyphase parallelism behaves largely as expected. Throughput scales nearly linearly with the parallel factor, while per-channel timing stays in roughly the same range. The non-pipelined \(L=2\) and \(L=3\) designs look especially strong in throughput per ALM because they avoid the additional register overhead required by deep pipelines. If the goal is maximum raw throughput, the pipelined \(L=3\) design is the strongest option, but it achieves that performance with a clear area and power cost.

MCM with CSD ends up occupying a more specialized part of the design space. It performs worse in ALM usage, but better in DSP usage, and it ended up more power-efficient than I initially expected. That makes it appealing in cases where preserving DSP blocks matters more than minimizing logic consumption. It also still feels like an unfinished optimization opportunity in a productive sense. The repeated CSE patterns identified in Section 4.6 suggest that a more sophisticated optimizer could likely reduce the shift-add count further.

| Architecture | Fmax (MHz) | Throughput (Msps) | ALMs | DSPs | Dynamic Power (mW) | Throughput/ALM (Ksps/ALM) | Throughput/mW (Msps/mW) |
|---|---|---|---|---|---|---|---|
| Direct-form | 38.7 | 38.7 | 1,125 | 96 | 39.0 | 34.4 | 0.99 |
| Pipelined | 58.7 | 58.7 | 3,042 | 96 | 100.5 | 19.3 | 0.58 |
| L=2 parallel | 37.1 | 74.1 | 1,696 | 192 | 73.3 | 43.7 | 1.01 |
| L=3 parallel | 36.4 | 109.2 | 2,499 | 288 | 105.7 | 43.7 | 1.03 |
| L=3 parallel + pipeline | 58.3 | 174.8 | 7,589 | 288 | 343.9 | 23.0 | 0.51 |
| MCM direct-form | 33.2 | 33.2 | 5,033 | 0 | 17.9 | 6.6 | 1.86 |
| MCM pipelined | 58.6 | 58.6 | 5,651 | 0 | 30.7 | 10.4 | 1.91 |

*TABLE 14: Architecture Efficiency Comparison*

### 6.2 Hybrid MCM-DSP Architecture (Future Work)
One architecture I did not implement, but would like to explore next, is a hybrid multiplier mapping strategy. In that approach, small-magnitude coefficients with low nonzero digit (NZD) count would remain in CSD-based shift-add fabric, while the larger coefficients would be mapped to DSP blocks. For example, a coefficient such as \(h(6) = 136 = 2^3 + 2^7\) requires only two shift-add terms and is very inexpensive to keep in logic. In contrast, a coefficient such as \(h(95) = 216{,}278\), with 9 nonzero digits and 8 cascaded add operations, is a much stronger candidate for DSP implementation.

A hybrid partition like this could reduce ALM usage relative to the pure MCM design by offloading the most expensive shift-add chains into DSP blocks. At the same time, it could reduce DSP usage relative to the pure DSP design by keeping the simplest coefficients in fabric. In this design, roughly 30 coefficients have NZD \(\leq 3\), which means they can be realized with only one or two adders each and are likely much cheaper than assigning an entire DSP block. This approach could also improve timing, since the longest CSD chains currently dominate the critical path and appear to be the main reason the MCM version is limited to about 33.2 MHz.

The partitioning rule itself would become its own optimization problem. Choosing the NZD threshold at which a coefficient should move from logic into a DSP would require balancing ALM usage, DSP usage, dynamic power, and timing closure. That makes this a natural next step emerging from the current project.

### 6.3 Conclusion
By the end of the project, it felt like much more than just building an FIR filter. It became an exercise in repeatedly asking how much farther the same design could be pushed through better structural decisions. Quantization was manageable, but only after I stopped treating it as a secondary detail. \(Q=20\) turned out to be the point where the stopband target survived rounding without making the coefficients any wider than necessary. Reaching that point by moving beyond the 100-tap baseline made the numerical side of the problem easier, but it also made the hardware side more demanding. For timing, pipelining was by far the strongest lever. Once the reduction tree was broken into registered stages, all of the pipelined versions converged to roughly 58.3 to 58.7 MHz. Without pipelining, the long combinational summation path kept \(F_{\max}\) in the 33 to 39 MHz range. In that sense, the timing data made the design decision difficult to argue against. Polyphase decomposition was the cleanest way I found to increase throughput. The non-pipelined \(L=3\) version in particular delivers a large throughput gain for the amount of hardware it uses. That was one of the clearest moments where a course concept stopped being just a block diagram and became something measurable that I could compare directly.

The MCM/CSD approach also proved to be more than a side curiosity. It gives up timing and logic area, but it eliminates DSP usage entirely and does so with the lowest dynamic power in the design set. Working through those trade-offs, especially where area could be reduced or critical path depth could be shortened, was a large part of what made the project rewarding from a learning perspective.

## 7. References
[1] Course Project Specification: `Supporting_Documentation/Project.pdf`

[2] MATLAB `firpm` documentation: https://www.mathworks.com/help/signal/ref/firpm.html

[3] K. K. Parhi, *VLSI Digital Signal Processing Systems: Design and Implementation*, Wiley, 1999, Ch. 8–11.

## 8. Acknowledgements
GitHub Copilot was used primarily to improve efficiency. Because this work required seven separate Quartus runs, there was a significant amount of repetitive compile-check-report effort. Copilot helped accelerate that workflow by assisting with routine iteration, identifying obvious warnings or errors, and helping review timing and area reports. However, the underlying design decisions, RTL development, and analysis were my own. Its role was limited to reducing the overhead of repetitive tasks.
