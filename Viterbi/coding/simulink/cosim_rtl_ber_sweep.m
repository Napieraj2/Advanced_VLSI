function cosim_rtl_ber_sweep(varargin)
% COSIM_RTL_BER_SWEEP  File-based RTL cosim BER sweep for both Viterbi decoders.
%
% Drives ../verilog/viterbi_soft_decoder.v and viterbi_hard_decoder.v with the
% same channel chain that Viterbi_Simulink_Model.slx feeds into the toolbox
% Viterbi blocks (BPSK + AWGN, optionally soft-quantized to signed int8 with
% NOM_LEVEL = 48).  Stimulus is written to text files, ModelSim runs the RTL
% once per branch per sweep, and decoded bits are read back to compute BER
% per Eb/N0 point.  Output goes to plots/cosim_rtl_ber.png and
% plots/cosim_rtl_ber.csv.
%
% Each Eb/N0 point is driven as one continuous N_BITS_PER_POINT-bit payload
% (plus 2 tail bits) with a single cold-start reset at the top of the point.
% This relies on NORMALIZE = 1 in viterbi_soft_decoder.v to keep the 16-bit
% signed path metric bounded; the hard decoder's metric is bounded to
% {-2, 0, +2} per symbol intrinsically.
%
% Optional name/value arguments:
%   'EbN0'             [0:1:8]   Eb/N0 grid in dB (length must match the
%                                N_POINTS parameter compiled into the TBs;
%                                this script overrides it via -G).
%   'NBitsPerPoint'    10000     Payload bits per Eb/N0 point.
%   'NomLevel'         48        Soft-input scale factor (matches the AWGN TBs).
%   'Branch'           'both'    'soft' | 'hard' | 'both'
%   'VlogExe'          'vlog'    Path override for ModelSim vlog/vsim.
%   'VsimExe'          'vsim'
%
% Requires: Communications Toolbox (poly2trellis, convenc) and a ModelSim /
% Questa install on PATH (vlog + vsim).

p = inputParser;
addParameter(p, 'EbN0',           0:1:8);
addParameter(p, 'NBitsPerPoint',  10000);
addParameter(p, 'NomLevel',       48);
addParameter(p, 'Branch',         'both');
addParameter(p, 'VlogExe',        'vlog');
addParameter(p, 'VsimExe',        'vsim');
parse(p, varargin{:});
EbN0_dB         = p.Results.EbN0(:).';
N_BITS_PER_POINT= p.Results.NBitsPerPoint;
NOM_LEVEL       = p.Results.NomLevel;
branch          = lower(p.Results.Branch);
vlogExe         = p.Results.VlogExe;
vsimExe         = p.Results.VsimExe;

here       = fileparts(mfilename('fullpath'));
verilogDir = fullfile(here, '..', 'verilog');
plotsDir   = fullfile(here, 'plots');
if ~exist(plotsDir, 'dir'); mkdir(plotsDir); end

CODE_RATE = 1/2;
TAIL_BITS = 2;
TOTAL_BITS_PER_POINT = N_BITS_PER_POINT + TAIL_BITS;
trellis = poly2trellis(3, [7 5]);

rng(2026);  % reproducible

% Pre-generate per-point payload + AWGN samples.  Same payload used for soft
% & hard so the two BER columns are directly comparable on a common
% Monte-Carlo realization.
N_POINTS = numel(EbN0_dB);
all_data  = zeros(N_BITS_PER_POINT,  N_POINTS, 'uint8');
all_soft0 = zeros(TOTAL_BITS_PER_POINT, N_POINTS, 'int16');
all_soft1 = zeros(TOTAL_BITS_PER_POINT, N_POINTS, 'int16');
all_hard0 = zeros(TOTAL_BITS_PER_POINT, N_POINTS, 'uint8');
all_hard1 = zeros(TOTAL_BITS_PER_POINT, N_POINTS, 'uint8');

for ip = 1:N_POINTS
    EbN0 = EbN0_dB(ip);
    sigma = sqrt(1/(2*CODE_RATE*10^(EbN0/10)));   % real-axis std dev (N0/2)
    data = randi([0 1], N_BITS_PER_POINT, 1);
    coded = convenc([data; zeros(TAIL_BITS,1)], trellis);
    % RTL soft convention (README §3.3): positive soft -> bit 1.
    % BPSK map matches tb_viterbi_soft_decoder_awgn.v: coded=1 -> +NOM, 0 -> -NOM.
    bpsk  = 2*double(coded) - 1;     % 0 -> -1, 1 -> +1
    rx    = bpsk + sigma*randn(size(bpsk));
    rx_pairs = reshape(rx, 2, []).';
    s = round(NOM_LEVEL*rx_pairs);
    s = max(-127, min(127, s));
    h = double(rx_pairs > 0);          % hard slice: rx>0 => sent 1
    all_data (:,ip) = uint8(data);
    all_soft0(:,ip) = int16(s(:,1));
    all_soft1(:,ip) = int16(s(:,2));
    all_hard0(:,ip) = uint8(h(:,1));
    all_hard1(:,ip) = uint8(h(:,2));
end

results = struct('EbN0', EbN0_dB, ...
                 'BER_soft_rtl', nan(1,N_POINTS), ...
                 'err_soft_rtl', zeros(1,N_POINTS), ...
                 'BER_hard_rtl', nan(1,N_POINTS), ...
                 'err_hard_rtl', zeros(1,N_POINTS), ...
                 'bits',         N_BITS_PER_POINT*ones(1,N_POINTS));

% -------------------------------------------------------------------------
% Soft branch
% -------------------------------------------------------------------------
if any(strcmp(branch, {'soft','both'}))
    fprintf('### Soft cosim: %d points x %d bits/point (continuous, no intra-point reset)\n', ...
            N_POINTS, N_BITS_PER_POINT);
    stim = fullfile(verilogDir, 'stim_soft.txt');
    out  = fullfile(verilogDir, 'dec_soft.txt');
    write_pairs_int(stim, all_soft0, all_soft1);

    [rc, log] = run_modelsim(verilogDir, vlogExe, vsimExe, ...
        {'viterbi_soft_decoder.v', 'tb_viterbi_soft_decoder_cosim.v'}, ...
        'tb_viterbi_soft_decoder_cosim', ...
        struct('N_BITS_PER_POINT', N_BITS_PER_POINT, ...
               'N_POINTS',         N_POINTS));
    if rc ~= 0; disp(log); error('ModelSim soft run failed'); end

    dec = read_dec_file(out, N_BITS_PER_POINT, N_POINTS);
    [results.BER_soft_rtl, results.err_soft_rtl] = score(dec, all_data);
end

% -------------------------------------------------------------------------
% Hard branch
% -------------------------------------------------------------------------
if any(strcmp(branch, {'hard','both'}))
    fprintf('### Hard cosim: %d points x %d bits/point (continuous, no intra-point reset)\n', ...
            N_POINTS, N_BITS_PER_POINT);
    stim = fullfile(verilogDir, 'stim_hard.txt');
    out  = fullfile(verilogDir, 'dec_hard.txt');
    write_pairs_int(stim, all_hard0, all_hard1);

    [rc, log] = run_modelsim(verilogDir, vlogExe, vsimExe, ...
        {'viterbi_hard_decoder.v', 'tb_viterbi_hard_decoder_cosim.v'}, ...
        'tb_viterbi_hard_decoder_cosim', ...
        struct('N_BITS_PER_POINT', N_BITS_PER_POINT, ...
               'N_POINTS',         N_POINTS));
    if rc ~= 0; disp(log); error('ModelSim hard run failed'); end

    dec = read_dec_file(out, N_BITS_PER_POINT, N_POINTS);
    [results.BER_hard_rtl, results.err_hard_rtl] = score(dec, all_data);
end

% -------------------------------------------------------------------------
% Report + plot
% -------------------------------------------------------------------------
fprintf('\nEb/N0 (dB) | bits     | err_soft | BER_soft_rtl | err_hard | BER_hard_rtl\n');
fprintf('-----------+----------+----------+--------------+----------+--------------\n');
for ip = 1:N_POINTS
    fprintf('  %5.1f    | %8d | %8d | %.3e    | %8d | %.3e\n', ...
            EbN0_dB(ip), results.bits(ip), ...
            results.err_soft_rtl(ip), results.BER_soft_rtl(ip), ...
            results.err_hard_rtl(ip), results.BER_hard_rtl(ip));
end

T = table(EbN0_dB(:), results.bits(:), ...
          results.err_soft_rtl(:), results.BER_soft_rtl(:), ...
          results.err_hard_rtl(:), results.BER_hard_rtl(:), ...
          'VariableNames', {'EbN0_dB','bits','err_soft_rtl','BER_soft_rtl', ...
                            'err_hard_rtl','BER_hard_rtl'});
csvPath = fullfile(plotsDir, 'cosim_rtl_ber.csv');
writetable(T, csvPath);
fprintf('Wrote %s\n', csvPath);

f = figure('Color','w','Position',[100 100 720 480]);
floor_v = 0.5/max(results.bits);
y_soft = max(results.BER_soft_rtl, floor_v);
y_hard = max(results.BER_hard_rtl, floor_v);
semilogy(EbN0_dB, y_soft, '-o', 'LineWidth',1.6, 'DisplayName','Soft RTL'); hold on;
semilogy(EbN0_dB, y_hard, '-s', 'LineWidth',1.6, 'DisplayName','Hard RTL');
grid on; xlabel('E_b/N_0 (dB)'); ylabel('BER');
title(sprintf('RTL cosim BER (%d bits/point)', results.bits(1)));
legend('Location','southwest'); ylim([floor_v*0.5 1]);
pngPath = fullfile(plotsDir, 'cosim_rtl_ber.png');
exportgraphics(f, pngPath, 'Resolution', 150);
close(f);
fprintf('Wrote %s\n', pngPath);

end

% =========================================================================
function write_pairs_int(path, A, B)
% Flatten A and B (same size) into one "a b" decimal-int line per element.
A = double(A(:));
B = double(B(:));
fid = fopen(path, 'w');
if fid < 0; error('Cannot open %s for writing', path); end
fprintf(fid, '%d %d\n', [A.'; B.']);
fclose(fid);
end

function [rc, log] = run_modelsim(workDir, vlogExe, vsimExe, srcFiles, top, gParams)
% Run a ModelSim batch compile + simulate from workDir.  Returns combined log.
% gParams is a containers.Map (or struct) of top-level parameter overrides.
if nargin < 6; gParams = struct(); end
oldDir = cd(workDir);
cleaner = onCleanup(@() cd(oldDir));
% Fresh work library
if exist('work', 'dir'); try; rmdir('work', 's'); catch; end; end
[rc, l1] = system(sprintf('vlib work'));
if rc ~= 0; log = l1; return; end
src = sprintf(' "%s"', srcFiles{:});
cmd = sprintf('"%s" -quiet -work work%s', vlogExe, src);
[rc, l2] = system(cmd);
if rc ~= 0; log = sprintf('%s\n%s', l1, l2); return; end
gFlags = '';
if isstruct(gParams)
    fn = fieldnames(gParams);
    for i = 1:numel(fn); gFlags = [gFlags sprintf(' -G%s=%g', fn{i}, gParams.(fn{i}))]; end %#ok<AGROW>
end
cmd = sprintf('"%s" -c -quiet%s -do "run -all; quit -f" %s', vsimExe, gFlags, top);
[rc, l3] = system(cmd);
log = sprintf('%s\n%s\n%s', l1, l2, l3);
end

function dec = read_dec_file(path, NBITS, N_POINTS)
fid = fopen(path, 'r');
if fid < 0; error('Cannot open %s', path); end
% Lines are either 0/1 or 'X' (uninitialized).  Read all then parse.
raw = textscan(fid, '%s', NBITS*N_POINTS);
fclose(fid);
raw = raw{1};
v = nan(numel(raw),1);
for i = 1:numel(raw)
    s = raw{i};
    if ~isempty(s) && (s(1) == '0' || s(1) == '1')
        v(i) = double(s(1)) - double('0');
    end
end
expected = NBITS*N_POINTS;
if numel(v) ~= expected
    warning('cosim_rtl_ber_sweep:length', ...
            'Decoded file %s has %d lines, expected %d', path, numel(v), expected);
    if numel(v) > expected; v = v(1:expected); end
    if numel(v) < expected; v(end+1:expected) = NaN; end
end
dec = reshape(v, NBITS, N_POINTS);
end

function [BER, errs] = score(dec, data)
% dec, data: NBITS x N_POINTS  (data is uint8, dec is double w/ NaN)
N_POINTS = size(dec, 2);
BER  = nan(1, N_POINTS);
errs = zeros(1, N_POINTS);
for ip = 1:N_POINTS
    d  = double(data(:,ip));
    r  = dec(:,ip);
    valid = ~isnan(r);
    e = sum(d(valid) ~= r(valid));
    n = sum(valid);
    errs(ip) = e;
    if n > 0; BER(ip) = e / n; else; BER(ip) = NaN; end
end
end
