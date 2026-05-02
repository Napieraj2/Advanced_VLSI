function build_viterbi_simulink_model()
% BUILD_VITERBI_SIMULINK_MODEL  Generate Viterbi_Simulink_Model.slx.
%
% Builds a Simulink block-diagram BER tester that mirrors
% Viterbi_Decoder_Project.m: rate-1/2, K=3, (7,5)_8 convolutional code,
% AWGN channel, parallel hard- and soft-decision Viterbi decoders sharing
% the same trellis. Produces side-by-side BER readouts that should agree
% with the .m-script sweep within Monte-Carlo tolerance.
%
% Run from the simulink/ folder:
%   >> build_viterbi_simulink_model
%   >> open_system('Viterbi_Simulink_Model')
%   >> sim('Viterbi_Simulink_Model')
%
% Requires: Simulink, Communications Toolbox, DSP System Toolbox.
%
% Note: Communications Toolbox library paths vary slightly between MATLAB
% releases. add_block_safe() below searches a list of known aliases so the
% script keeps working across versions. If your release introduces yet
% another library path, add it to the alias table at the bottom of this
% file or build the model by hand following the block list in README.md.

modelName = 'Viterbi_Simulink_Model';
if bdIsLoaded(modelName); close_system(modelName, 0); end
new_system(modelName);
open_system(modelName);

% --- Model-wide parameters (visible inside blocks via base workspace) -----
assignin('base','TRELLIS',  poly2trellis(3, [7 5]));
assignin('base','TB_DEPTH', 12);
assignin('base','SOFT_BITS', 3);
assignin('base','EbN0_dB',  4);     % single operating point for the .slx
assignin('base','CODE_RATE', 1/2);

% --- Blocks ----------------------------------------------------------------
% Keep parameter overrides minimal; many of the toolbox dialog parameters
% (SeedSource enum strings, AWGN noise mode names, etc.) drift between
% MATLAB releases. Defaults are usable and only the things we genuinely
% need to override for the BER comparison are set explicitly.
add_block_safe('BernoulliBinaryGenerator',  modelName, 'BitSrc',          [ 30  60  90 100], ...
    'ProbabilityOfZero', '0.5', ...
    'SamplesPerFrame',   '1');
add_block_safe('ConvolutionalEncoder',      modelName, 'ConvEnc',         [140  60 220 100], ...
    'trellis', 'TRELLIS');
add_block_safe('BPSKModulator',             modelName, 'BPSK_Mod',        [260  60 340 100]);
add_block_safe('AWGNChannel',               modelName, 'AWGN',            [380  60 460 100], ...
    'Variance',    '1/(2*CODE_RATE*10^(EbN0_dB/10))');

% Hard branch
add_block_safe('BPSKDemodulator',           modelName, 'BPSK_Demod_Hard', [500  30 580  70]);
add_block_safe('ViterbiDecoder',            modelName, 'Viterbi_Hard',    [600  30 700  70], ...
    'trellis',  'TRELLIS', ...
    'tbdepth',  'TB_DEPTH', ...
    'opmode',   'Truncated', ...
    'dectype',  'Hard decision');
add_block_safe('ErrorRateCalculation',      modelName, 'BER_Hard',        [740  30 820  70], ...
    'WsName', 'BER_hard');

% Soft branch (quantize AWGN samples to SOFT_BITS levels)
% BPSK Modulator emits complex baseband; the Quantizing Encoder needs a
% real input, so extract the real part before quantizing. The imaginary
% component carries only noise after the AWGN channel and is discarded
% (this matches optimal coherent soft demodulation for BPSK).
add_block('built-in/ComplexToRealImag', [modelName '/Re_Soft'], ...
    'Position', [475 110 495 150], 'Output', 'Real');
add_block_safe('QuantizingEncoder',         modelName, 'Quantizer',       [510 110 590 150], ...
    'partition', 'linspace(-1, 1, 2^SOFT_BITS - 1)', ...
    'codebook',  '0:(2^SOFT_BITS - 1)');
add_block_safe('ViterbiDecoder',            modelName, 'Viterbi_Soft',    [600 110 700 150], ...
    'trellis',  'TRELLIS', ...
    'tbdepth',  'TB_DEPTH', ...
    'opmode',   'Truncated', ...
    'dectype',  'Soft Decision', ...
    'nsdecb',   'SOFT_BITS');
add_block_safe('ErrorRateCalculation',      modelName, 'BER_Soft',        [740 110 820 150], ...
    'WsName', 'BER_soft');

% --- Wiring ----------------------------------------------------------------
add_line(modelName, 'BitSrc/1',          'ConvEnc/1',         'autorouting','on');
add_line(modelName, 'ConvEnc/1',         'BPSK_Mod/1',        'autorouting','on');
add_line(modelName, 'BPSK_Mod/1',        'AWGN/1',            'autorouting','on');

add_line(modelName, 'AWGN/1',            'BPSK_Demod_Hard/1', 'autorouting','on');
add_line(modelName, 'BPSK_Demod_Hard/1', 'Viterbi_Hard/1',    'autorouting','on');
add_line(modelName, 'Viterbi_Hard/1',    'BER_Hard/2',        'autorouting','on');
add_line(modelName, 'BitSrc/1',          'BER_Hard/1',        'autorouting','on');

add_line(modelName, 'AWGN/1',            'Re_Soft/1',         'autorouting','on');
add_line(modelName, 'Re_Soft/1',         'Quantizer/1',       'autorouting','on');
add_line(modelName, 'Quantizer/1',       'Viterbi_Soft/1',    'autorouting','on');
add_line(modelName, 'Viterbi_Soft/1',    'BER_Soft/2',        'autorouting','on');
add_line(modelName, 'BitSrc/1',          'BER_Soft/1',        'autorouting','on');

% --- Solver / runtime ------------------------------------------------------
set_param(modelName, 'Solver',     'FixedStepDiscrete', ...
                     'FixedStep',  '1', ...
                     'StopTime',   '1e5');

save_system(modelName, [modelName '.slx']);
fprintf('Built %s.slx\n', modelName);
fprintf('Open with: open_system(''%s'')\n', modelName);
fprintf('Run with:  sim(''%s''); disp(BER_soft); disp(BER_hard);\n', modelName);
end

% ---------------------------------------------------------------------------
function add_block_safe(kind, modelName, name, pos, varargin)
% Add a Communications Toolbox block by *logical* name, trying a list of
% known library paths so this script survives MATLAB-version drift.
aliases  = block_aliases(kind);
last_err = [];
for i = 1:numel(aliases)
    try
        % Make sure the source library is loaded so add_block can find it.
        lib = strtok(aliases{i}, '/');
        try; load_system(lib); catch; end %#ok<CTCH>
        add_block(aliases{i}, [modelName '/' name], 'Position', pos, varargin{:});
        return;
    catch ME
        last_err = ME;
    end
end
if isempty(last_err)
    msg = '(no aliases registered)';
else
    msg = last_err.message;
end
error('build_viterbi_simulink_model:UnknownBlock', ...
      ['Could not add block "%s".\n' ...
       'Last underlying error: %s\n' ...
       'See README.md for the manual block-by-block build recipe.'], ...
      kind, msg);
end

function paths = block_aliases(kind)
% Real Simulink library block names contain embedded newlines (the
% display label wraps onto multiple lines), so we build them with
% sprintf to make the \n explicit.
nl = char(10);
switch kind
    case 'BernoulliBinaryGenerator'
        paths = {['commrandsrc3/Bernoulli Binary' nl 'Generator'], ...
                 ['commrandsrc2/Bernoulli Binary' nl 'Generator']};
    case 'ConvolutionalEncoder'
        paths = {['commcnvcod2/Convolutional' nl 'Encoder'], ...
                 ['commcnvcod3/Convolutional' nl 'Encoder']};
    case 'ViterbiDecoder'
        paths = {'commcnvcod2/Viterbi Decoder', ...
                 'commcnvcod3/Viterbi Decoder'};
    case 'BPSKModulator'
        paths = {['commdigbbndpm3/BPSK' nl 'Modulator' nl 'Baseband']};
    case 'BPSKDemodulator'
        paths = {['commdigbbndpm3/BPSK' nl 'Demodulator' nl 'Baseband']};
    case 'AWGNChannel'
        paths = {['commchan3/AWGN' nl 'Channel'], ...
                 ['commchan2/AWGN' nl 'Channel']};
    case 'QuantizingEncoder'
        paths = {['commsrccod2/Quantizing' nl 'Encoder']};
    case 'ErrorRateCalculation'
        paths = {['commsink2/Error Rate' nl 'Calculation'], ...
                 ['commsink3/Error Rate' nl 'Calculation']};
    otherwise
        paths = {};
end
end
