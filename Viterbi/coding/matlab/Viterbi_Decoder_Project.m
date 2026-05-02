clc; clear; close all;

%% ========================================================================
%  Viterbi Decoder Tradeoff Study  Advanced VLSI Course Project
%  ========================================================================
%  Reference design: rate-1/2, K = 3 convolutional code, generators (7, 5)_8.
%  This is the same code implemented in:
%      Viterbi/coding/verilog/viterbi_soft_decoder.v   (SOFT_W = 8)
%      Viterbi/coding/verilog/viterbi_hard_decoder.v
%
%  Purpose:
%    1. Run a BER-vs-Eb/N0 sweep over an AWGN channel and decode with
%       MATLAB's vitdec() in both 'hard' and 'soft' modes, using the same
%       trellis and traceback depth as the RTL.
%    2. Plot soft / hard / uncoded BER curves and report coding gain at
%       BER = 1e-4.
%    3. Cross-reference the algorithmic results against the FPGA tradeoffs
%       (ALMs / registers / Fmax) extracted from the two Quartus revisions.
%  ========================================================================

%% 1  Code & Decoder Parameters (must match RTL)
K            = 3;                       % constraint length
gen_oct      = [7 5];                   % generator polynomials, octal
trellis      = poly2trellis(K, gen_oct);
code_rate    = 1/2;
TB_DEPTH     = 12;                      % matches RTL TB_DEPTH
SOFT_BITS    = 3;                       % vitdec soft-decision precision (bits)

% Sanity check: encoder must agree with the Verilog enc_out function.
%   Verilog: c0 = u XOR s1 XOR s0   (g0 = 7)
%            c1 = u XOR s0           (g1 = 5)
% MATLAB convenc emits one [c0 c1] pair per input bit.  We test both
% generators against an all-zero starting state since MATLAB's internal
% state numbering does not have to match the Verilog (s1, s0) ordering;
% only the input/output mapping has to.
fprintf('========== Encoder Sanity Check ==========\n');
test_bits = [1 0 1 1 0 0 1 0];
c_matlab  = convenc(test_bits, trellis);
% Reference computation using the (s1, s0) convention from the Verilog enc_out.
c_ref = zeros(1, 2*numel(test_bits));
s1 = 0; s0 = 0;
for i = 1:numel(test_bits)
    u  = test_bits(i);
    c_ref(2*i-1) = bitxor(bitxor(u, s1), s0);  % c0
    c_ref(2*i)   = bitxor(u, s0);              % c1
    s0 = s1; s1 = u;
end
fprintf('  input bits     : %s\n', mat2str(test_bits));
fprintf('  MATLAB convenc : %s\n', mat2str(c_matlab));
fprintf('  Verilog enc_out: %s\n', mat2str(c_ref));
if isequal(c_matlab, c_ref)
    fprintf('  --> match\n');
else
    warning('Encoder mismatch between MATLAB trellis and Verilog enc_out.');
end

%% 2  Message generation
rng(20260501,'twister');
N_bits   = 1e6;                         % data bits per Eb/N0 point
tail     = zeros(1, K-1);               % flush bits (matches RTL drain idea)
tx_bits  = [randi([0 1], 1, N_bits), tail];
coded    = convenc(tx_bits, trellis);   % column-pairs: [c0 c1 c0 c1 ...]
bpsk_tx  = 1 - 2*coded;                 % 0 -> +1, 1 -> -1

%% 3  Eb/N0 Sweep
% Add real-valued AWGN with variance N0/2 per sample so that BPSK BER follows
% the textbook Q(sqrt(2*Eb/N0)).  awgn() with 'measured' would treat the
% requested SNR as (signal power)/(noise variance), which on a real-only
% channel gives noise variance N0 (not N0/2) and produces curves that are
% optimistically shifted by ~3 dB; we therefore generate noise manually.
EbN0_dB   = 0:0.5:10;
ber_soft  = zeros(size(EbN0_dB));
ber_hard  = zeros(size(EbN0_dB));
ber_uncod = zeros(size(EbN0_dB));

% For SOFT_BITS = 3 (8 levels), vitdec wants unsigned values in [0, 7]
% with 0 = strong 1 and 7 = strong 0.
soft_levels = 2^SOFT_BITS;

fprintf('\n========== BER Sweep ==========\n');
fprintf('%-8s %-12s %-12s %-12s\n','Eb/N0','BER soft','BER hard','BER uncoded');

for k = 1:numel(EbN0_dB)
    EbN0_lin = 10^(EbN0_dB(k)/10);

    % Coded channel: each transmitted symbol carries Es = code_rate * Eb,
    % so the per-symbol SNR is reduced by 10*log10(code_rate).
    sigma_coded = sqrt(1 / (2 * code_rate * EbN0_lin));
    rx          = bpsk_tx + sigma_coded * randn(size(bpsk_tx));

    % --- Hard-decision path -------------------------------------------------
    rx_hard    = (rx < 0);                           % BPSK slicer: '+' -> 0, '-' -> 1
    dec_hard   = vitdec(rx_hard, trellis, TB_DEPTH, 'term', 'hard');
    ber_hard(k)= mean(dec_hard(1:N_bits) ~= tx_bits(1:N_bits));

    % --- Soft-decision path -------------------------------------------------
    % Map rx -> integer in [0, soft_levels-1] (0 = strong 1, max = strong 0).
    % Clip to +/- 1 (one nominal symbol amplitude) before quantizing.
    rx_clipped = max(min(rx, 1), -1);
    rx_soft    = round((1 - rx_clipped) / 2 * (soft_levels - 1));
    rx_soft    = max(0, min(soft_levels-1, rx_soft));
    dec_soft   = vitdec(rx_soft, trellis, TB_DEPTH, 'term', 'soft', SOFT_BITS);
    ber_soft(k)= mean(dec_soft(1:N_bits) ~= tx_bits(1:N_bits));

    % --- Uncoded reference --------------------------------------------------
    sigma_unc  = sqrt(1 / (2 * EbN0_lin));
    uncoded_tx = 1 - 2*tx_bits;
    rx_unc     = uncoded_tx + sigma_unc * randn(size(uncoded_tx));
    dec_unc    = (rx_unc < 0);
    ber_uncod(k)= mean(dec_unc(1:N_bits) ~= tx_bits(1:N_bits));

    fprintf('%-8.1f %-12.3e %-12.3e %-12.3e\n', ...
            EbN0_dB(k), ber_soft(k), ber_hard(k), ber_uncod(k));
end

%% 4  Coding Gain at BER = 1e-4 (linear interpolation in semilogy space)
target_ber = 1e-4;
ebn0_at = @(curve) interp_ebn0(curve, EbN0_dB, target_ber);
ebn0_soft  = ebn0_at(ber_soft);
ebn0_hard  = ebn0_at(ber_hard);
ebn0_uncod = ebn0_at(ber_uncod);

fprintf('\n========== Coding Gain @ BER = 1e-4 ==========\n');
fprintf('Uncoded BPSK    Eb/N0 : %s dB\n', fmt_db(ebn0_uncod));
fprintf('Hard Viterbi    Eb/N0 : %s dB  (gain vs uncoded: %s dB)\n', ...
        fmt_db(ebn0_hard),  fmt_db(ebn0_uncod - ebn0_hard));
fprintf('Soft Viterbi    Eb/N0 : %s dB  (gain vs uncoded: %s dB)\n', ...
        fmt_db(ebn0_soft),  fmt_db(ebn0_uncod - ebn0_soft));
fprintf('Soft over Hard advantage : %s dB\n', fmt_db(ebn0_hard - ebn0_soft));

%% 5  BER Plot
fig = figure('Name','Viterbi BER: Soft vs Hard','Color','w');
semilogy(EbN0_dB, ber_uncod, 'k--o', 'LineWidth', 1.4, 'DisplayName','Uncoded BPSK'); hold on;
semilogy(EbN0_dB, ber_hard,  'r-s',  'LineWidth', 1.6, 'DisplayName','Hard Viterbi');
semilogy(EbN0_dB, ber_soft,  'b-^',  'LineWidth', 1.6, 'DisplayName','Soft Viterbi (3-bit)');
grid on; xlabel('E_b/N_0 (dB)'); ylabel('BER');
title(sprintf('Rate-1/2, K=%d, (7,5)_8 Viterbi  BER vs E_b/N_0', K));
ylim([1e-6 1]); legend('Location','southwest');

if ~exist('plots','dir'); mkdir('plots'); end
saveas(fig, fullfile('plots','ber_soft_vs_hard.png'));
fprintf('\nSaved BER plot to plots/ber_soft_vs_hard.png\n');

% Also write a CSV with the sweep data so Figure 1 can be regenerated
% from numbers, matching the pattern used by the Simulink and cosim flows.
ber_table = table(EbN0_dB(:), ber_soft(:), ber_hard(:), ber_uncod(:), ...
    'VariableNames', {'EbN0_dB','BER_soft','BER_hard','BER_uncoded'});
writetable(ber_table, fullfile('plots','ber_soft_vs_hard.csv'));
fprintf('Saved BER table to plots/ber_soft_vs_hard.csv\n');

%% 6  Hardware Tradeoff Summary
% Post-fit numbers from the two Cyclone V revisions in
% Viterbi/coding/verilog/quartus/, target 5CGXFC9E7F35C8 @ 100 MHz.
% Pulled from output_files/<rev>.fit.summary and <rev>.sta.rpt
% (Slow 1100 mV 85 C corner).
hw = struct();
hw.soft.alms      = 410;
hw.soft.regs      = 211;
hw.soft.fmax_mhz  = 32.32;
hw.soft.slack_ns  = -20.94;
hw.hard.alms      = 346;
hw.hard.regs      = 192;
hw.hard.fmax_mhz  = 23.64;
hw.hard.slack_ns  = -32.30;

fprintf('\n========== FPGA Tradeoff (Cyclone V 5CGXFC9E7F35C8 @ 100 MHz target) ==========\n');
fprintf('%-10s %-10s %-10s %-12s %-14s\n','Decoder','ALMs','Regs','Fmax (MHz)','Coding gain');
fprintf('%-10s %-10s %-10s %-12s %-14s\n', ...
        'Soft', fmt_int(hw.soft.alms), fmt_int(hw.soft.regs), ...
        fmt_num(hw.soft.fmax_mhz),     sprintf('%s dB', fmt_db(ebn0_uncod - ebn0_soft)));
fprintf('%-10s %-10s %-10s %-12s %-14s\n', ...
        'Hard', fmt_int(hw.hard.alms), fmt_int(hw.hard.regs), ...
        fmt_num(hw.hard.fmax_mhz),     sprintf('%s dB', fmt_db(ebn0_uncod - ebn0_hard)));
fprintf(['\nTradeoff summary:\n', ...
         '  - Soft decoder pays an area premium (wider branch-metric adders,\n', ...
         '    SOFT_W-bit signed datapath) for ~%s dB additional coding gain over hard.\n', ...
         '  - Both decoders miss the 100 MHz target on Cyclone V because the\n', ...
         '    single-cycle ACS+%d-deep traceback combinational chain dominates\n', ...
         '    the critical path. Pipelining the ACS and converting the survivor\n', ...
         '    history to register-exchange would close this gap; see README \n', ...
         '    section 9 (Notes and Possible Extensions).\n'], ...
         fmt_db(ebn0_hard - ebn0_soft), TB_DEPTH);

%% --- Helpers ---------------------------------------------------------------
function s = fmt_db(x)
    if isnan(x); s = '  N/A'; else; s = sprintf('%5.2f', x); end
end
function s = fmt_num(x)
    if isnan(x); s = 'TBD'; else; s = sprintf('%.1f', x); end
end
function s = fmt_int(x)
    if isnan(x); s = 'TBD'; else; s = sprintf('%d', round(x)); end
end
function ebn0 = interp_ebn0(curve, EbN0_dB, target_ber)
% Monotonize the BER curve (drop non-decreasing samples that would break
% interp1) and interpolate Eb/N0 at the target BER in log-BER space.
    [c, ix] = unique(curve, 'stable');
    e       = EbN0_dB(ix);
    mask    = c > 0 & isfinite(c);
    c       = c(mask); e = e(mask);
    if numel(c) < 2 || target_ber > max(c) || target_ber < min(c)
        ebn0 = NaN; return;
    end
    [c_sorted, ord] = sort(c, 'descend');
    e_sorted = e(ord);
    ebn0 = interp1(log10(c_sorted), e_sorted, log10(target_ber), 'linear', NaN);
end
