clc; clear; close all;

%% ========================================================================
%  FIR Lowpass Filter Design — OVERFLOW CONTROL (32-bit Output, Saturation)
%  ========================================================================
%  Same filter specification and coefficients as OVERFLOW_PREVENT:
%    - 192 taps, Q=20, 21-bit signed coefficients, 80 dB stopband
%  Difference: output is saturated to 32-bit signed instead of using a
%  full 38-bit accumulator at the output.  Internal tree operates at 38-bit
%  precision; only the final output assignment is clamped.
%  ========================================================================

%% 1 — Filter Specification (IDENTICAL to OVERFLOW_PREVENT)
Fp       = 0.20;
Fs_edge  = 0.23;
target_atten = 80;                  % dB — same 80 dB requirement
max_passband_ripple = 0.5;

f = [0 Fp Fs_edge 1];
a = [1 1 0 0];

%% 2 — Joint Tap-Count / Weight Tuning (same algorithm as OVERFLOW_PREVENT)
numTaps = 100;

while numTaps <= 500
    N = numTaps - 1;

    w_stop = 50;
    design_ok = false;
    while w_stop <= 1e6
        w = [1 w_stop];
        b = firpm(N, f, a, w);

        [H, wvec] = freqz(b, 1, 4096);
        magdB = 20*log10(abs(H) + 1e-12);

        stopIdx = (wvec/pi) >= Fs_edge;
        passIdx = (wvec/pi) <= Fp;
        As = -max(magdB(stopIdx));
        Rp = max(magdB(passIdx)) - min(magdB(passIdx));

        if As >= target_atten && Rp <= max_passband_ripple
            design_ok = true;
            break;
        elseif As < target_atten
            w_stop = w_stop * 1.3;
        else
            break;
        end
    end

    if design_ok, break; end

    % Increase taps (keep even for Type I symmetry)
    numTaps = numTaps + 2;
end

N = numTaps - 1;

fprintf('========== Filter Design Results (OVERFLOW CONTROL) ==========\n');
fprintf('Taps: %d  |  Order: %d\n', numTaps, N);
fprintf('Stopband weight used: %.1f\n', w_stop);
fprintf('Stopband attenuation: %.2f dB  (target >= %d dB)\n', As, target_atten);
fprintf('Passband ripple: %.4f dB  (target <= %.1f dB)\n', Rp, max_passband_ripple);

%% 3 — Coefficient Quantisation (Q=20 required for 80 dB — same as PREVENT)
%  Sweep Q from 8 to 24 to confirm Q=20 is the minimum for 80 dB.
Q_candidates = 8:2:24;
As_q_results = zeros(size(Q_candidates));

fprintf('\n========== Quantisation Sweep ==========\n');
fprintf('%-8s  %-22s  %-10s\n', 'Q bits', 'Stopband Atten (dB)', 'Pass?');
fprintf('%s\n', repmat('-', 1, 44));

for idx = 1:length(Q_candidates)
    Qtry = Q_candidates(idx);
    bq_try = round(b * 2^Qtry) / 2^Qtry;
    [Hq_try, ~] = freqz(bq_try, 1, 4096);
    magdBq_try = 20*log10(abs(Hq_try) + 1e-12);
    As_q_results(idx) = -max(magdBq_try(stopIdx));
    fprintf('%-8d  %-22.2f  %-10s\n', Qtry, As_q_results(idx), ...
            mat2str(As_q_results(idx) >= target_atten));
end

Q = 20;                             % same Q as OVERFLOW_PREVENT — required for 80 dB
fprintf('\nSelected Q = %d bits (same as OVERFLOW_PREVENT — required for 80 dB)\n', Q);

%% 4 — Final Quantised Coefficients
bq = round(b * 2^Q) / 2^Q;
[Hq, wvecq] = freqz(bq, 1, 4096);
magdB_q = 20*log10(abs(Hq) + 1e-12);
As_q = -max(magdB_q(stopIdx));
Rp_q = max(magdB_q(passIdx)) - min(magdB_q(passIdx));
fprintf('Quantised stopband attenuation (Q=%d): %.2f dB\n', Q, As_q);
fprintf('Quantised passband ripple (Q=%d): %.4f dB\n', Q, Rp_q);

%% 5 — Coefficient Symmetry
nCoeffs = length(bq);
sym_pairs = [];
for i = 1:floor(nCoeffs/2)
    j = nCoeffs - i + 1;
    if bq(i) == bq(j)
        sym_pairs = [sym_pairs; i j];
    end
end

fprintf('\n========== Coefficient Symmetry ==========\n');
fprintf('Symmetric pairs: %d / %d possible\n', size(sym_pairs,1), floor(nCoeffs/2));
if size(sym_pairs,1) == floor(nCoeffs/2)
    fprintf('All pairs symmetric — linear phase confirmed.\n');
    fprintf('Unique multipliers needed: %d (half of %d taps).\n', ...
            ceil(nCoeffs/2), nCoeffs);
end

%% 6 — Accumulator Overflow Analysis (38-bit internal, 32-bit output)
W_input = 16;
W_coeff = Q + 1;                    % Q fractional + 1 sign = 21 bits
W_mult  = W_input + W_coeff;
W_acc   = 38;                       % internal tree precision (same as PREVENT)
W_out   = 32;                       % saturated output width

coeff_int    = round(bq * 2^Q);
worst_sum    = sum(abs(coeff_int));
max_input    = 2^(W_input - 1) - 1;  % 32767
worst_accum  = worst_sum * max_input;

W_accum_needed = ceil(log2(double(worst_accum) + 1)) + 1;

fprintf('\n========== Overflow Analysis (32-bit Output Saturation) ==========\n');
fprintf('Input width:           %d bits (signed)\n', W_input);
fprintf('Coefficient width:     %d bits (Q%d + sign)\n', W_coeff, Q);
fprintf('Multiply width:        %d bits\n', W_mult);
fprintf('Internal tree width:   %d bits (full precision)\n', W_acc);
fprintf('Output width:          %d bits (saturated)\n', W_out);
fprintf('Worst-case accum:      %s\n', num2str(worst_accum));
fprintf('Bits required (exact): %d bits\n', W_accum_needed);

overflow_ratio = worst_accum / (2^(W_out-1) - 1);
fprintf('Max 32-bit signed:     %d\n', 2^(W_out-1) - 1);
fprintf('Overflow ratio:        %.1fx  (worst-case exceeds 32-bit by this factor)\n', overflow_ratio);

% Step-response test: does the DC convergence value overflow?
dc_sum = sum(coeff_int);
step_val = 1000;
step_accum = dc_sum * step_val;
fprintf('\nStep response (din=1000):  acc = %d\n', step_accum);
fprintf('  Fits in 32 bits?  %s  (%d < %d)\n', ...
    mat2str(abs(step_accum) <= 2^(W_out-1)-1), abs(step_accum), 2^(W_out-1)-1);

% Minimum input to trigger overflow
min_overflow_input = floor((2^(W_out-1)-1) / worst_sum);
fprintf('\nOverflow threshold:  |din| > %d  (with adversarial tap alignment)\n', min_overflow_input);
fprintf('  Full-scale input:  %d  →  overflow ratio = %.1fx\n', max_input, overflow_ratio);
fprintf('  Typical audio (-20 dBFS):  ~%d  →  NO overflow\n', round(max_input * 0.1));

%% 7 — Compare with OVERFLOW_PREVENT design
fprintf('\n========== Design Comparison ==========\n');
fprintf('%-30s  %-20s  %-20s\n', 'Parameter', 'OVERFLOW_PREVENT', 'OVERFLOW_CONTROL');
fprintf('%s\n', repmat('-', 1, 74));
fprintf('%-30s  %-20d  %-20d\n', 'Taps', 192, numTaps);
fprintf('%-30s  %-20d  %-20d\n', 'Q (fractional bits)', 20, Q);
fprintf('%-30s  %-20d  %-20d\n', 'Coeff width (bits)', 21, W_coeff);
fprintf('%-30s  %-20d  %-20d\n', 'Internal tree width', 38, W_acc);
fprintf('%-30s  %-20d  %-20d\n', 'Output width (bits)', 38, W_out);
fprintf('%-30s  %-20s  %-20s\n', 'Stopband atten (dB)', '80.1', num2str(As_q, '%.1f'));
fprintf('%-30s  %-20s  %-20s\n', 'Overflow strategy', 'Prevent (wide out)', 'Control (saturate)');

%% 8 — Plots
figure('Name', 'OVERFLOW CONTROL — Filter Response', 'Position', [100 100 900 700]);

subplot(2,2,1);
plot(wvec/pi, magdB, 'b', 'LineWidth', 1.5); hold on;
plot(wvecq/pi, magdB_q, 'r--', 'LineWidth', 1.2);
yline(-target_atten, 'k:', 'LineWidth', 1);
grid on;
xlabel('Normalized Frequency (\times\pi rad/sample)');
ylabel('Magnitude (dB)');
legend('Float', sprintf('Q=%d', Q), sprintf('-%d dB', target_atten), ...
       'Location', 'southwest');
title('Full Response');
ylim([-120 5]);

subplot(2,2,2);
plot(wvec/pi, magdB, 'b', 'LineWidth', 1.5); hold on;
plot(wvecq/pi, magdB_q, 'r--', 'LineWidth', 1.2);
grid on;
xlabel('Normalized Frequency (\times\pi rad/sample)');
ylabel('Magnitude (dB)');
title('Passband Detail');
xlim([0 Fp*1.2]); ylim([-0.5 0.5]);

subplot(2,2,3);
plot(wvec/pi, magdB, 'b', 'LineWidth', 1.5); hold on;
plot(wvecq/pi, magdB_q, 'r--', 'LineWidth', 1.2);
yline(-target_atten, 'k:', 'LineWidth', 1);
grid on;
xlabel('Normalized Frequency (\times\pi rad/sample)');
ylabel('Magnitude (dB)');
title('Stopband Detail');
xlim([Fs_edge 1]); ylim([-120 -40]);

subplot(2,2,4);
stem(0:N, b, 'b', 'MarkerSize', 3); hold on;
stem(0:N, bq, 'r.', 'MarkerSize', 3);
grid on;
xlabel('Tap Index');
ylabel('Coefficient Value');
legend('Float', sprintf('Q=%d', Q));
title('Coefficient Values');

figure('Name', 'OVERFLOW CONTROL — Quantisation Sweep');
bar(Q_candidates, As_q_results, 0.6);
hold on;
yline(target_atten, 'r--', 'LineWidth', 1.5);
xlabel('Coefficient Word Length Q (bits)');
ylabel('Stopband Attenuation (dB)');
title('Stopband Attenuation vs. Coefficient Quantisation');
grid on;

%% 9 — Export Integer Coefficients for Verilog
%  Same coefficients as OVERFLOW_PREVENT (Q=20, 21-bit signed)
fprintf('\n========== Verilog Coefficient Table ==========\n');
fprintf('// %d-tap FIR, Q%d fixed-point (%d-bit signed coefficients)\n', numTaps, Q, W_coeff);
fprintf('// %d unique coefficients (symmetric linear-phase)\n', ceil(numTaps/2));
fprintf('// OVERFLOW_CONTROL: internal 38-bit tree, output saturated to 32 bits\n');
halfN = ceil(numTaps / 2);
coeff_unique = coeff_int(1:halfN);
for k = 1:halfN
    fprintf('coeff[%2d] = %d''sd%d;\n', k-1, W_coeff, coeff_unique(k));
end

%% 10 — CSD Decomposition for MCM Architecture
function csd = to_csd(val)
    s = sign(val);
    v = abs(val);
    csd = zeros(0, 2);
    pos = 0;
    while v ~= 0
        if mod(v, 2) == 1
            if mod(v, 4) == 3
                csd(end+1, :) = [pos, -1]; %#ok<AGROW>
                v = v + 1;
            else
                csd(end+1, :) = [pos,  1]; %#ok<AGROW>
                v = v - 1;
            end
        end
        v = floor(v / 2);
        pos = pos + 1;
    end
    if s < 0
        csd(:,2) = -csd(:,2);
    end
end

csd_all  = cell(halfN, 1);
nzd_all  = zeros(halfN, 1);
for k = 1:halfN
    csd_all{k} = to_csd(coeff_unique(k));
    nzd_all(k) = size(csd_all{k}, 1);
end

totalNZD = sum(nzd_all);
fprintf('\n========== CSD Decomposition ==========\n');
fprintf('Coefficients: %d unique (symmetric half)\n', halfN);
fprintf('Total non-zero CSD digits: %d\n', totalNZD);
fprintf('Average NZD per coefficient: %.1f\n', totalNZD / halfN);
fprintf('Estimated add/sub operations: %d  (totalNZD - numCoeffs)\n', ...
        totalNZD - halfN);

fprintf('\n%-8s  %-12s  %-4s  %s\n', 'Index', 'Coeff', 'NZD', 'CSD Representation');
fprintf('%s\n', repmat('-', 1, 72));
for k = 1:halfN
    c = coeff_unique(k);
    d = csd_all{k};
    parts = cell(1, size(d,1));
    for j = 1:size(d,1)
        if d(j,2) > 0
            parts{j} = sprintf('+2^%d', d(j,1));
        else
            parts{j} = sprintf('-2^%d', d(j,1));
        end
    end
    str = strjoin(parts, ' ');
    fprintf('  %3d     %10d    %3d   %s\n', k-1, c, nzd_all(k), str);
end

fprintf('\n========== DONE — Run complete ==========\n');
fprintf('Next: use the exported coefficient table to build RTL in OVERFLOW_CONTROL/\n');
