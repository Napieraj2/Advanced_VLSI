clc; clear; close all;

%% ========================================================================
%  FIR Lowpass Filter Design — Advanced VLSI Course Project
%  ========================================================================
%  Specs:
%    Type           : Lowpass, linear phase (Type I — even order, symmetric)
%    Taps           : starts at 100, auto-increased if passband ripple > 0.5 dB
%    Passband edge  : 0.20 (normalized to Nyquist)
%    Stopband edge  : 0.23 (normalized to Nyquist)
%    Stopband atten : >= 80 dB
%    Passband ripple: <= 0.5 dB
%  Method: Parks-McClellan (firpm) equiripple design
%  ========================================================================

%% 1 — Filter Specification
numTaps = 100;                      % starting point — will increase if needed
Fp = 0.20;                          % passband edge, normalized to Nyquist
Fs_edge = 0.23;                     % stopband edge, normalized to Nyquist
target_atten = 80;                  % dB minimum stopband attenuation
max_passband_ripple = 0.5;          % dB — acceptable passband ripple

% firpm expects [0 Fp Fs 1] already Nyquist-normalized
f = [0 Fp Fs_edge 1];
a = [1 1 0 0];

%% 2 — Joint Tap-Count / Weight Tuning
%  Outer loop: increase taps if passband ripple is too large.
%  Inner loop: increase stopband weight until >= 80 dB stopband.
%  Stops when BOTH stopband AND passband specs are met.

while numTaps <= 500   % safety cap, if too large then very complex filter and specs likely unachievable
    N = numTaps - 1;   % order = taps - 1

    % --- inner: sweep stopband weight ---
    w_stop = 50;
    design_ok = false;
    while w_stop <= 1e6  % if too large Q will fail to converge, so cap it
        w = [1 w_stop];
        b = firpm(N, f, a, w);

        [H, wvec] = freqz(b, 1, 4096);
        magdB = 20*log10(abs(H) + 1e-12);

        stopIdx = (wvec/pi) >= Fs_edge;
        passIdx = (wvec/pi) <= Fp;
        As = -max(magdB(stopIdx));
        Rp = max(magdB(passIdx)) - min(magdB(passIdx));

        if As >= target_atten && Rp <= max_passband_ripple  % both specs met — design successful
            design_ok = true;
            break;
        elseif As < target_atten
            w_stop = w_stop * 1.3;   % need more stopband push
        else
            break;  % stopband OK but passband bad — need more taps
        end
    end

    if design_ok, break; end

    % Increase taps (keep even for Type I symmetry)
    numTaps = numTaps + 2;
end

N = numTaps - 1;

fprintf('========== Filter Design Results ==========\n');
fprintf('Taps: %d  |  Order: %d\n', numTaps, N);
fprintf('Stopband weight used: %.1f\n', w_stop);
fprintf('Stopband attenuation: %.2f dB  (target >= %d dB)\n', As, target_atten);
fprintf('Passband ripple: %.4f dB  (target <= %.1f dB)\n', Rp, max_passband_ripple);

%% 3 — Coefficient Quantization Word-Length Sweep
% Sweep Q from 14 to 24 to find the minimum word length that keeps >= 80 dB
Q_candidates = 14:1:24;
As_q_results = zeros(size(Q_candidates));

fprintf('\n========== Quantization Sweep ==========\n');
fprintf('%-8s  %-22s  %-10s\n', 'Q bits', 'Stopband Atten (dB)', 'Pass?');
fprintf('%s\n', repmat('-', 1, 44));

for idx = 1:length(Q_candidates) % loop over candidate Q values
    Qtry = Q_candidates(idx);
    bq_try = round(b * 2^Qtry) / 2^Qtry;
    [Hq_try, ~] = freqz(bq_try, 1, 4096);
    magdBq_try = 20*log10(abs(Hq_try) + 1e-12);
    As_q_results(idx) = -max(magdBq_try(stopIdx));
    fprintf('%-8d  %-22.2f  %-10s\n', Qtry, As_q_results(idx), ...
            mat2str(As_q_results(idx) >= target_atten));
end

Q_min_idx = find(As_q_results >= target_atten, 1, 'first'); % first Q that meets stopband spec after quantization

if isempty(Q_min_idx)
    Q = Q_candidates(end);
    warning('No tested Q achieves %d dB. Using Q = %d.', target_atten, Q);
else
    Q = Q_candidates(Q_min_idx);
end

fprintf('\nSelected Q = %d bits\n', Q);
fprintf('Reason: smallest word length preserving >= %d dB stopband after quantization.\n', target_atten);

%% 4 — Final Quantized Coefficients
bq = round(b * 2^Q) / 2^Q;
[Hq, wvecq] = freqz(bq, 1, 4096);
magdB_q = 20*log10(abs(Hq) + 1e-12);
As_q = -max(magdB_q(stopIdx));
fprintf('Quantized stopband attenuation (Q=%d): %.2f dB\n', Q, As_q);

%% 5 — Coefficient Symmetry (exploit linear phase)
% Type I FIR: bq(k) == bq(N+2-k) — halves the multiplier count in hardware
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
for k = 1:size(sym_pairs,1) % print each symmetric pair
    fprintf('  bq(%d) = bq(%d)  [value = %g]\n', ...
            sym_pairs(k,1), sym_pairs(k,2), bq(sym_pairs(k,1)));
end

if size(sym_pairs,1) == floor(nCoeffs/2) % all pairs symmetric
    fprintf('All pairs symmetric — linear phase confirmed.\n');
    fprintf('Unique multipliers needed: %d (half of %d taps).\n', ...
            ceil(nCoeffs/2), nCoeffs);
end

%% 6 — Accumulator Overflow Analysis
W_input = 16;                               % signed input data width
W_coeff = Q + 1;                            % Q fractional + 1 sign bit
W_mult  = W_input + W_coeff;                % multiply output width

coeff_int    = round(bq * 2^Q);             % integer representation
worst_sum    = sum(abs(coeff_int));
max_input    = 2^(W_input - 1) - 1;
worst_accum  = worst_sum * max_input;

W_accum_needed = ceil(log2(double(worst_accum) + 1)) + 1; % +1 for sign
W_accum_naive  = W_mult + ceil(log2(numTaps));

fprintf('\n========== Accumulator Overflow Analysis ==========\n');
fprintf('Input width:        %d bits (signed)\n', W_input);
fprintf('Coefficient width:  %d bits (Q%d + sign)\n', W_coeff, Q);
fprintf('Multiply width:     %d bits\n', W_mult);
fprintf('Naive accum width:  %d bits (mult + ceil(log2(%d)))\n', W_accum_naive, numTaps);
fprintf('Worst-case accum:   %s\n', num2str(worst_accum));
fprintf('Actual accum width: %d bits\n', W_accum_needed);
fprintf('Strategy: keep a %d-bit internal accumulator, then saturate the external output to 32 bits.\n', W_accum_needed);

%% 7 — Plots
% --- Full magnitude response ---
figure('Name', 'FIR Filter Response', 'Position', [100 100 900 700]);
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

% --- Passband detail ---
subplot(2,2,2);
plot(wvec/pi, magdB, 'b', 'LineWidth', 1.5); hold on;
plot(wvecq/pi, magdB_q, 'r--', 'LineWidth', 1.2);
grid on;
xlabel('Normalized Frequency (\times\pi rad/sample)');
ylabel('Magnitude (dB)');
title('Passband Detail');
xlim([0 Fp*1.2]); ylim([-0.5 0.5]);

% --- Stopband detail ---
subplot(2,2,3);
plot(wvec/pi, magdB, 'b', 'LineWidth', 1.5); hold on;
plot(wvecq/pi, magdB_q, 'r--', 'LineWidth', 1.2);
yline(-target_atten, 'k:', 'LineWidth', 1);
grid on;
xlabel('Normalized Frequency (\times\pi rad/sample)');
ylabel('Magnitude (dB)');
title('Stopband Detail');
xlim([Fs_edge 1]); ylim([-120 -40]);

% --- Coefficient stem plot ---
subplot(2,2,4);
stem(0:N, b, 'b', 'MarkerSize', 3); hold on;
stem(0:N, bq, 'r.', 'MarkerSize', 3);
grid on;
xlabel('Tap Index');
ylabel('Coefficient Value');
legend('Float', sprintf('Q=%d', Q));
title('Coefficient Values');

% --- Q sweep bar chart ---
figure('Name', 'Quantization Sweep');
bar(Q_candidates, As_q_results, 0.6);
hold on;
yline(target_atten, 'r--', 'LineWidth', 1.5);
xlabel('Coefficient Word Length Q (bits)');
ylabel('Stopband Attenuation (dB)');
title('Stopband Attenuation vs. Coefficient Quantization');
grid on;

%% 8 — Export Integer Coefficients for Verilog
coeff_int = round(b * 2^Q);
fprintf('\n========== Verilog Coefficient Table ==========\n');
fprintf('// %d-tap FIR, Q%d fixed-point (%d-bit signed coefficients)\n', numTaps, Q, W_coeff);
fprintf('// %d unique coefficients (symmetric linear-phase)\n', ceil(numTaps/2));
for k = 1:numTaps
    fprintf('assign coeff[%2d] = %d;\n', k-1, coeff_int(k));
end

%% 9 — CSD Decomposition & MCM Shift-Add Network Generation
% =========================================================================
%  Canonic Signed Digit (CSD) representation minimises the number of
%  non-zero digits in a signed binary number.  Property: no two consecutive
%  digits are both non-zero.  Each non-zero digit requires one add/subtract
%  and one shift; CSD minimises the total.
%
%  After CSD, we search for "common sub-expressions" (CSE) of the form
%  (x << a) ± (x << b) that appear across multiple coefficients so we can
%  compute them once and reuse.
% =========================================================================

% --- 9a. CSD conversion --------------------------------------------------
% CSD encodes |c| with digit set {-1, 0, +1}, no two adjacent non-zero.
% Returns Nx2 matrix: column 1 = bit position, column 2 = sign (+1 or -1).

function csd = to_csd(val)
    s = sign(val);
    v = abs(val);
    csd = zeros(0, 2);
    pos = 0;
    while v ~= 0
        if mod(v, 2) == 1
            if mod(v, 4) == 3          % run of 1s → replace with -1 here, carry +1
                csd(end+1, :) = [pos, -1];
                v = v + 1;
            else
                csd(end+1, :) = [pos,  1];
                v = v - 1;
            end
        end
        v = floor(v / 2);
        pos = pos + 1;
    end
    if s < 0 % if original value was negative, flip signs
        csd(:,2) = -csd(:,2);
    end
end

% Compute CSD for the 96 unique (symmetric-half) coefficients
halfN = ceil(numTaps / 2);
coeff_unique = coeff_int(1:halfN);     % first 96 coefficients

csd_all  = cell(halfN, 1);            % CSD digit arrays
nzd_all  = zeros(halfN, 1);           % non-zero digit count per coeff

for k = 1:halfN % loop over unique coefficients
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
fprintf('\nComparison to direct multiply:\n');
fprintf('  DSP multipliers eliminated:  96\n');
fprintf('  Shift-add ops required:      %d\n', totalNZD - halfN);

% Print CSD for each coefficient
fprintf('\n%-8s  %-12s  %-4s  %s\n', 'Index', 'Coeff', 'NZD', 'CSD Representation');
fprintf('%s\n', repmat('-', 1, 72));

for k = 1:halfN % loop over unique coefficients
    c = coeff_unique(k);
    d = csd_all{k};
    
    % Build readable string: +2^a -2^b +2^c ...
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
    
    % Verify reconstruction
    check = sum(d(:,2) .* 2.^d(:,1));
    assert(check == c, 'CSD mismatch for coeff[%d]: got %d, expected %d', k-1, check, c);
end
fprintf('\nAll %d CSD decompositions verified (reconstruction = original).\n', halfN);

% --- 9b. Common Sub-Expression (CSE) analysis ----------------------------
% Look for pairs (shift_a, shift_b) where (x<<a ± x<<b) appears in
% multiple coefficients.  Each reuse saves one add/sub.

fprintf('\n========== Common Sub-Expression Analysis ==========\n');

% Extract all pairwise "fundamentals" from each coefficient's CSD
pair_map = containers.Map('KeyType', 'char', 'ValueType', 'any');
for k = 1:halfN
    d = csd_all{k};
    nd = size(d, 1);
    if nd < 2, continue; end
    for i = 1:nd
        for j = i+1:nd
            % Normalise: smaller shift first, relative shifts
            sa = d(i,1); sb = d(j,1);
            si = d(i,2); sj = d(j,2);
            if sa > sb
                [sa, sb] = deal(sb, sa);
                [si, sj] = deal(sj, si);
            end
            % Key: relative sign and shift difference (sign of first is +)
            relSign = si * sj;    % +1 means same sign (add), -1 means subtract
            diff = sb - sa;
            key = sprintf('%+d:%d', relSign, diff);
            if pair_map.isKey(key)
                pair_map(key) = [pair_map(key), k-1];
            else
                pair_map(key) = k-1;
            end
        end
    end
end

% Sort by reuse count (most shared first)
keys = pair_map.keys;
counts = cellfun(@(k) numel(pair_map(k)), keys);
[counts_sorted, idx] = sort(counts, 'descend');
keys_sorted = keys(idx);

fprintf('%-20s  %-6s  %s\n', 'Sub-expression', 'Reuses', 'Coefficient indices');
fprintf('%s\n', repmat('-', 1, 72));
for i = 1:min(20, length(keys_sorted))
    k = keys_sorted{i};
    c = pair_map(k);
    % Parse key back
    tok = sscanf(k, '%d:%d');
    if tok(1) > 0
        opStr = sprintf('(x<<%d) + (x<<%d)', 0, tok(2));
    else
        opStr = sprintf('(x<<%d) - (x<<%d)', 0, tok(2));
    end
    fprintf('  %-18s  %4d    [%s]\n', opStr, counts_sorted(i), ...
            strjoin(arrayfun(@num2str, c, 'Uni', false), ', '));
end

% --- 9c. Generate Verilog MCM shift-add network ---------------------------
fprintf('\n========== Verilog MCM Shift-Add Expressions ==========\n');
fprintf('// Each product[k] = preadd[k] * coeff[k] replaced by shift-add\n');
fprintf('// preadd width = %d bits (W_IN+1), output width = %d bits\n', ...
        W_input + 1, W_input + W_coeff);
fprintf('// Total shift-add operations: %d  (vs 96 DSP multipliers)\n\n', ...
        totalNZD - halfN);

for k = 1:halfN
    c = coeff_unique(k);
    d = csd_all{k};
    nd = size(d, 1);
    
    if c == 0
        fprintf('assign product[%2d] = 0;  // coeff = 0\n', k-1);
        continue;
    end
    
    % Build Verilog expression from CSD digits
    % First non-zero digit initialises, rest are add/sub
    terms = cell(1, nd);
    for j = 1:nd
        shift = d(j, 1);
        if shift == 0
            shiftStr = sprintf('pa_%d', k-1);
        else
            shiftStr = sprintf('(pa_%d <<< %d)', k-1, shift);
        end
        if d(j, 2) > 0
            terms{j} = sprintf('+ %s', shiftStr);
        else
            terms{j} = sprintf('- %s', shiftStr);
        end
    end
    expr = strjoin(terms, ' ');
    % Clean leading '+ '
    if expr(1) == '+'
        expr = strtrim(expr(2:end));
    end
    fprintf('assign product[%2d] = %s;  // %d  (%d ops)\n', ...
            k-1, expr, c, nd - 1);
end

fprintf('\n// MCM summary: 0 DSP blocks, %d add/sub operations, %d shifts (free in hardware)\n', ...
        totalNZD - halfN, totalNZD);