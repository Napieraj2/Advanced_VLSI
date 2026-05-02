function results = run_simulink_ber_sweep(varargin)
% RUN_SIMULINK_BER_SWEEP  Sweep Eb/N0 in the Simulink BER tester.
%
%   results = run_simulink_ber_sweep()                % default 0:8 dB grid
%   results = run_simulink_ber_sweep('EbN0', 0:0.5:8) % custom grid
%   results = run_simulink_ber_sweep('StopTime', 5e5) % bits per point
%
% Sweeps EbN0_dB across the grid, runs the Simulink model at each point,
% and returns a struct with BER tables for the toolbox hard and soft
% decoders. Also produces:
%   plots/simulink_ber_sweep.png   - BER vs Eb/N0 plot
%   plots/simulink_ber_sweep.csv   - tab-separated BER table
%
% The model must already exist; build it once with
%   build_viterbi_simulink_model
% (with or without 'IncludeHDLCosim') before calling this.
%
% Pairs with §8.2 of Viterbi/README.md.

p = inputParser;
addParameter(p, 'EbN0',     0:1:8,    @(x) isnumeric(x) && isvector(x));
addParameter(p, 'StopTime', 5e5,      @(x) isnumeric(x) && isscalar(x));
addParameter(p, 'Model',    'Viterbi_Simulink_Model', @ischar);
parse(p, varargin{:});
EbN0_grid = p.Results.EbN0(:);
stopTime  = p.Results.StopTime;
modelName = p.Results.Model;

if ~bdIsLoaded(modelName)
    if exist([modelName '.slx'], 'file')
        load_system(modelName);
    else
        error('Model %s.slx not found. Run build_viterbi_simulink_model first.', modelName);
    end
end

% Make sure the parameters the model expects exist in base workspace.
if evalin('base','~exist(''TRELLIS'',''var'')')
    assignin('base','TRELLIS',  poly2trellis(3, [7 5]));
    assignin('base','TB_DEPTH', 12);
    assignin('base','SOFT_BITS', 3);
    assignin('base','CODE_RATE', 1/2);
end

set_param(modelName, 'StopTime', num2str(stopTime));

N = numel(EbN0_grid);
ber_soft  = zeros(N,1);
ber_hard  = zeros(N,1);
errs_soft = zeros(N,1);
errs_hard = zeros(N,1);
bits      = zeros(N,1);

fprintf('Eb/N0 (dB) | bits     | err_soft | BER_soft   | err_hard | BER_hard\n');
fprintf('-----------+----------+----------+------------+----------+-----------\n');
for k = 1:N
    assignin('base', 'EbN0_dB', EbN0_grid(k));
    sim(modelName);
    bs = evalin('base', 'BER_soft');   % [BER errors total]
    bh = evalin('base', 'BER_hard');
    ber_soft(k)  = bs(1);
    errs_soft(k) = bs(2);
    ber_hard(k)  = bh(1);
    errs_hard(k) = bh(2);
    bits(k)      = bs(3);
    fprintf('%8.1f   | %8d | %8d | %.3e | %8d | %.3e\n', ...
        EbN0_grid(k), bits(k), errs_soft(k), ber_soft(k), errs_hard(k), ber_hard(k));
end

results = struct( ...
    'EbN0_dB', EbN0_grid, ...
    'bits',    bits, ...
    'errs_soft', errs_soft, 'BER_soft', ber_soft, ...
    'errs_hard', errs_hard, 'BER_hard', ber_hard);

here    = fileparts(mfilename('fullpath'));
plotDir = fullfile(here, 'plots');
if ~exist(plotDir, 'dir'); mkdir(plotDir); end

% --- Plot --------------------------------------------------------------
fig = figure('Visible','off','Color','w','Position',[100 100 720 480]);
ax  = axes(fig); %#ok<LAXES>
% Replace zeros with NaN so semilogy doesn't drop the point silently.
plot_soft = ber_soft;  plot_soft(plot_soft == 0) = NaN;
plot_hard = ber_hard;  plot_hard(plot_hard == 0) = NaN;
semilogy(ax, EbN0_grid, plot_hard, '-o', 'LineWidth', 1.5, 'DisplayName', 'Hard (toolbox)');
hold(ax,'on');
semilogy(ax, EbN0_grid, plot_soft, '-s', 'LineWidth', 1.5, 'DisplayName', 'Soft (toolbox, 3-bit)');
grid(ax,'on'); box(ax,'on');
xlabel(ax, 'E_b/N_0 (dB)'); ylabel(ax, 'BER');
title(ax, sprintf('Simulink BER sweep — Viterbi (7,5)_8, K=3, %d bits/point', stopTime));
legend(ax, 'Location', 'southwest');
ylim(ax, [1e-6 1]);
pngPath = fullfile(plotDir, 'simulink_ber_sweep.png');
exportgraphics(ax, pngPath, 'Resolution', 150);
close(fig);
fprintf('Wrote %s\n', pngPath);

% --- CSV ---------------------------------------------------------------
csvPath = fullfile(plotDir, 'simulink_ber_sweep.csv');
fid = fopen(csvPath, 'w');
fprintf(fid, 'EbN0_dB\tbits\terrs_soft\tBER_soft\terrs_hard\tBER_hard\n');
for k = 1:N
    fprintf(fid, '%.2f\t%d\t%d\t%.4e\t%d\t%.4e\n', ...
        EbN0_grid(k), bits(k), errs_soft(k), ber_soft(k), errs_hard(k), ber_hard(k));
end
fclose(fid);
fprintf('Wrote %s\n', csvPath);
end
