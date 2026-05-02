function build_viterbi_simulink_model(varargin)
% BUILD_VITERBI_SIMULINK_MODEL  Generate Viterbi_Simulink_Model.slx.
%
% Builds a Simulink block-diagram BER tester that mirrors
% Viterbi_Decoder_Project.m: rate-1/2, K=3, (7,5)_8 convolutional code,
% AWGN channel, parallel hard- and soft-decision Viterbi decoders sharing
% the same trellis. Produces side-by-side BER readouts that should agree
% with the .m-script sweep within Monte-Carlo tolerance.
%
% Optional name/value arguments:
%   'IncludeHDLCosim' (false)  Add HDL Cosimulation branches that exercise
%                              the pipelined RTL in ../verilog/ alongside
%                              the toolbox reference decoders. Requires
%                              HDL Verifier and a supported HDL simulator
%                              (ModelSim/Questa). When enabled, this
%                              function also writes cosim_hard.do and
%                              cosim_soft.do launch scripts next to the
%                              .slx so you can spawn the simulator with
%                                  vsim -do cosim_hard.do
%
% Run from the simulink/ folder:
%   >> build_viterbi_simulink_model                       % toolbox-only
%   >> build_viterbi_simulink_model('IncludeHDLCosim',true)
%   >> open_system('Viterbi_Simulink_Model')
%   >> sim('Viterbi_Simulink_Model')
%
% Requires: Simulink, Communications Toolbox, DSP System Toolbox.
%   With 'IncludeHDLCosim',true also: HDL Verifier + ModelSim/Questa.
%
% Note: Communications Toolbox library paths vary slightly between MATLAB
% releases. add_block_safe() below searches a list of known aliases so the
% script keeps working across versions. If your release introduces yet
% another library path, add it to the alias table at the bottom of this
% file or build the model by hand following the block list in README.md.

p = inputParser;
addParameter(p, 'IncludeHDLCosim', false, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
includeCosim = logical(p.Results.IncludeHDLCosim);

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
    'NoiseMethod', 'Variance', ...
    'VarianceSource', 'Parameter', ...
    'Variance',    '1/(CODE_RATE*10^(EbN0_dB/10))');  % complex AWGN: total var; real-axis noise = Variance/2 = N0/2

% Hard branch
add_block_safe('BPSKDemodulator',           modelName, 'BPSK_Demod_Hard', [500  30 580  70]);
add_block_safe('ViterbiDecoder',            modelName, 'Viterbi_Hard',    [760  30 860  70], ...
    'trellis',  'TRELLIS', ...
    'tbdepth',  'TB_DEPTH', ...
    'opmode',   'Continuous', ...
    'dectype',  'Hard decision');
add_block_safe('ErrorRateCalculation',      modelName, 'BER_Hard',        [1120  40 1200  80], ...
    'WsName', 'BER_hard');
% Continuous-mode Viterbi delays its output by TB_DEPTH samples; align the
% transmit reference using an explicit Delay block (mask parameter for the
% built-in 'Receive delay' field is named differently across MATLAB releases).
add_block('simulink/Discrete/Delay', [modelName '/Tx_Delay_Hard'], ...
    'Position', [640 0 700 30], 'DelayLength', 'TB_DEPTH');

% Soft branch (quantize AWGN samples to SOFT_BITS levels)
% BPSK Modulator emits complex baseband; we take the real part. Imag is
% pure noise after AWGN with phase offset 0 and is discarded (matches
% optimal coherent soft demodulation for BPSK).
%
% We build the soft-bit map with primitive blocks instead of the
% Communications Toolbox 'Quantizing Encoder' because that block's
% output port semantics (index vs. quantized value) and parameter names
% drift between releases. Mapping built here:
%       real_sample = +1  (sent bit 0) ->  soft = 0          (confident 0)
%       real_sample =  0  (uncertain)  ->  soft = (2^N-1)/2  (mid)
%       real_sample = -1  (sent bit 1) ->  soft = 2^N-1      (confident 1)
% Implemented as:  soft = round( clip( (1 - x) * (2^N-1)/2, 0, 2^N-1 ) )
add_block('built-in/ComplexToRealImag', [modelName '/Re_Soft'], ...
    'Position', [500 110 520 150], 'Output', 'Real');
% (1 - x) via 'Bias' block: y = u + (-1) followed by negation in Gain.
add_block('simulink/Math Operations/Bias', [modelName '/Soft_Bias'], ...
    'Position', [540 110 570 150], 'Bias', '-1');
add_block('simulink/Math Operations/Gain', [modelName '/Soft_Gain'], ...
    'Position', [610 110 650 150], ...
    'Gain', '-(2^SOFT_BITS - 1)/2');
add_block('simulink/Discontinuities/Saturation', [modelName '/Soft_Sat'], ...
    'Position', [670 110 700 150], ...
    'UpperLimit', '2^SOFT_BITS - 1', ...
    'LowerLimit', '0');
% Round-to-nearest then cast to uint8 (Viterbi soft expects an unsigned
% integer of width nsdec).
add_block_safe('DataTypeConversion', modelName, 'Soft_to_uint', [730 110 790 150], ...
    'OutDataTypeStr', 'uint8', ...
    'RndMeth', 'Nearest');
add_block_safe('ViterbiDecoder',            modelName, 'Viterbi_Soft',    [820 110 900 150], ...
    'trellis',  'TRELLIS', ...
    'tbdepth',  'TB_DEPTH', ...
    'opmode',   'Continuous', ...
    'dectype',  'Soft Decision', ...
    'nsdecb',   'SOFT_BITS');
% Decoder output inherits uint8 from the soft input; BER expects double on
% both ports, so cast back before the comparator.
add_block_safe('DataTypeConversion', modelName, 'Soft_out_to_dbl', [955 110 1015 150], ...
    'OutDataTypeStr', 'double');
add_block_safe('ErrorRateCalculation',      modelName, 'BER_Soft',        [1115 120 1195 160], ...
    'WsName', 'BER_soft');
add_block('simulink/Discrete/Delay', [modelName '/Tx_Delay_Soft'], ...
    'Position', [655 185 715 215], 'DelayLength', 'TB_DEPTH');

% --- Wiring ----------------------------------------------------------------
add_line(modelName, 'BitSrc/1',          'ConvEnc/1',         'autorouting','on');
add_line(modelName, 'ConvEnc/1',         'BPSK_Mod/1',        'autorouting','on');
add_line(modelName, 'BPSK_Mod/1',        'AWGN/1',            'autorouting','on');

add_line(modelName, 'AWGN/1',            'BPSK_Demod_Hard/1', 'autorouting','on');
add_line(modelName, 'BPSK_Demod_Hard/1', 'Viterbi_Hard/1',    'autorouting','on');
add_line(modelName, 'Viterbi_Hard/1',    'BER_Hard/2',        'autorouting','on');
add_line(modelName, 'BitSrc/1',          'Tx_Delay_Hard/1',   'autorouting','on');
add_line(modelName, 'Tx_Delay_Hard/1',   'BER_Hard/1',        'autorouting','on');

add_line(modelName, 'AWGN/1',            'Re_Soft/1',         'autorouting','on');
add_line(modelName, 'Re_Soft/1',         'Soft_Bias/1',       'autorouting','on');
add_line(modelName, 'Soft_Bias/1',       'Soft_Gain/1',       'autorouting','on');
add_line(modelName, 'Soft_Gain/1',       'Soft_Sat/1',        'autorouting','on');
add_line(modelName, 'Soft_Sat/1',        'Soft_to_uint/1',    'autorouting','on');
add_line(modelName, 'Soft_to_uint/1',    'Viterbi_Soft/1',    'autorouting','on');
add_line(modelName, 'Viterbi_Soft/1',    'Soft_out_to_dbl/1', 'autorouting','on');
add_line(modelName, 'Soft_out_to_dbl/1', 'BER_Soft/2',        'autorouting','on');
add_line(modelName, 'BitSrc/1',          'Tx_Delay_Soft/1',   'autorouting','on');
add_line(modelName, 'Tx_Delay_Soft/1',   'BER_Soft/1',        'autorouting','on');

% --- Solver / runtime ------------------------------------------------------
set_param(modelName, 'Solver',     'FixedStepDiscrete', ...
                     'FixedStep',  '1', ...
                     'StopTime',   '1e5');

% --- Optional HDL Cosimulation branches (RTL vs. toolbox cross-check) -----
if includeCosim
    add_hdl_cosim_branches(modelName);
    write_cosim_do_files();
end

save_system(modelName, [modelName '.slx']);
fprintf('Built %s.slx\n', modelName);
fprintf('Open with: open_system(''%s'')\n', modelName);
fprintf('Run with:  sim(''%s''); disp(BER_soft); disp(BER_hard);\n', modelName);
if includeCosim
    fprintf(['HDL Cosim branches added. Launch ModelSim/Questa first with:\n' ...
             '   vsim -do cosim_hard.do      %% then sim() the model\n' ...
             '   vsim -do cosim_soft.do      %% (separate session)\n' ...
             'Open each HDL Cosimulation block dialog once to bind it to\n' ...
             'the running simulator session (Connection tab) -- HDL Verifier\n' ...
             'does not expose every dialog parameter to set_param across\n' ...
             'releases, so the connection step is left manual on purpose.\n']);
end
end

% ---------------------------------------------------------------------------
function add_block_safe(kind, modelName, name, pos, varargin)
% Add a Communications Toolbox block by *logical* name, trying a list of
% known library paths so this script survives MATLAB-version drift.
%
% Two-pass strategy:
%   1) try add_block(alias, dst, 'Position', pos)  -- no extra params.
%      The first alias whose underlying library actually contains the
%      block wins. This isolates "wrong library path" failures from
%      "wrong dialog parameter name" failures.
%   2) apply varargin via set_param, so a stale parameter name produces
%      a clear, actionable error against the *real* block path instead
%      of falling through to a broken alias.
aliases  = block_aliases(kind);
add_errs = cell(0);
dstPath  = [modelName '/' name];
added    = false;
for i = 1:numel(aliases)
    try
        lib = strtok(aliases{i}, '/');
        try; load_system(lib); catch; end %#ok<CTCH>
        add_block(aliases{i}, dstPath, 'Position', pos);
        added = true;
        break;
    catch ME
        add_errs{end+1} = sprintf('  %s -> %s', aliases{i}, ME.message); %#ok<AGROW>
    end
end
if ~added
    if isempty(add_errs); detail = '(no aliases registered)';
    else; detail = strjoin(add_errs, sprintf('\n')); end
    error('build_viterbi_simulink_model:UnknownBlock', ...
          ['Could not add block "%s". Tried:\n%s\n' ...
           'See README.md for the manual block-by-block build recipe.'], ...
          kind, detail);
end
if ~isempty(varargin)
    try
        set_param(dstPath, varargin{:});
    catch ME
        error('build_viterbi_simulink_model:BadBlockParam', ...
              ['Block "%s" was created at %s but a dialog parameter is\n' ...
               'unknown on this MATLAB release: %s\n' ...
               'Inspect available names with:  get_param(''%s'',''DialogParameters'')'], ...
              kind, dstPath, ME.message, dstPath);
    end
end
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
    case 'HDLCosimulation'
        % HDL Verifier ships a single library 'hdlverifier'. The block
        % name has wrapped onto two display lines for many years.
        paths = {['hdlverifier/HDL Cosimulation'], ...
                 ['hdlverifier/HDL' nl 'Cosimulation']};
    case 'Buffer'
        paths = {['dspbuff3/Buffer'], ...
                 ['dspbuff2/Buffer']};
    case 'Selector'
        paths = {'simulink/Signal Routing/Selector'};
    case 'DataTypeConversion'
        paths = {'simulink/Signal Attributes/Data Type Conversion'};
    case 'Constant'
        paths = {'simulink/Sources/Constant'};
    otherwise
        paths = {};
end
end

% ---------------------------------------------------------------------------
function add_hdl_cosim_branches(modelName)
% Build two extra branches that route the same demodulated/quantized
% samples into the pipelined RTL (../verilog/viterbi_hard_decoder.v and
% viterbi_soft_decoder.v) via HDL Verifier's HDL Cosimulation block.
%
% The RTL ports we need to drive / observe:
%   hard : in_valid, rx0, rx1                  -> decoded_valid, decoded_bit
%   soft : in_valid, soft0[7:0], soft1[7:0]    -> decoded_valid, decoded_bit
%
% Pairs of code bits/samples are deserialized with a Buffer block (length
% 2) so each Simulink frame presents both branches in parallel; in_valid
% is tied high (a Constant 1) since the testbench drives one symbol per
% sample tick.

% --- Hard cosim branch ----------------------------------------------------
add_block_safe('Buffer', modelName, 'Buf_Hard', [500 200 560 240], ...
    'N', '2', 'V', '0', 'ic', '0');
add_block_safe('Selector', modelName, 'Sel_Hard_rx0', [580 175 640 205], ...
    'IndexOptions', 'Index vector (dialog)', 'Indices', '1');
add_block_safe('Selector', modelName, 'Sel_Hard_rx1', [580 235 640 265], ...
    'IndexOptions', 'Index vector (dialog)', 'Indices', '2');
add_block_safe('Constant', modelName, 'InValid_Hard', [580 290 640 320], ...
    'Value', '1', 'OutDataTypeStr', 'boolean');
add_block_safe('HDLCosimulation', modelName, 'Viterbi_Hard_RTL', ...
    [680 180 800 280]);
add_block_safe('ErrorRateCalculation', modelName, 'BER_Hard_RTL', ...
    [840 200 920 240], 'WsName', 'BER_hard_rtl');

add_line(modelName, 'AWGN/1',                'Buf_Hard/1',         'autorouting','on');
add_line(modelName, 'Buf_Hard/1',            'Sel_Hard_rx0/1',     'autorouting','on');
add_line(modelName, 'Buf_Hard/1',            'Sel_Hard_rx1/1',     'autorouting','on');
% NOTE: HDL Cosim port order is set in the block dialog. Defaults assume
% input order (in_valid, rx0, rx1) and output order (decoded_valid,
% decoded_bit). Adjust in the dialog if your version reorders them.
add_line(modelName, 'InValid_Hard/1',        'Viterbi_Hard_RTL/1', 'autorouting','on');
add_line(modelName, 'Sel_Hard_rx0/1',        'Viterbi_Hard_RTL/2', 'autorouting','on');
add_line(modelName, 'Sel_Hard_rx1/1',        'Viterbi_Hard_RTL/3', 'autorouting','on');
add_line(modelName, 'Viterbi_Hard_RTL/2',    'BER_Hard_RTL/2',     'autorouting','on');
% Reuse the toolbox Tx delay tap. RTL adds an extra +1 pipeline cycle
% (PIPELINE=1) on top of the TB_DEPTH traceback delay; if the cosim BER
% reads ~0.5 due to misalignment, insert an extra unit Delay between
% Tx_Delay_Hard and BER_Hard_RTL/1 (or set its DelayLength to TB_DEPTH+1).
add_line(modelName, 'Tx_Delay_Hard/1',       'BER_Hard_RTL/1',     'autorouting','on');

% --- Soft cosim branch ----------------------------------------------------
% Convert the unsigned quantizer output (0..2^SOFT_BITS-1) to signed int8
% that matches the RTL's signed [SOFT_W-1:0] inputs. Center the levels
% around zero so 0 -> -127, max -> +127.
add_block_safe('Buffer', modelName, 'Buf_Soft', [500 360 560 400], ...
    'N', '2', 'V', '0', 'ic', '0');
add_block_safe('Selector', modelName, 'Sel_Soft_s0', [580 335 640 365], ...
    'IndexOptions', 'Index vector (dialog)', 'Indices', '1');
add_block_safe('Selector', modelName, 'Sel_Soft_s1', [580 395 640 425], ...
    'IndexOptions', 'Index vector (dialog)', 'Indices', '2');
add_block_safe('DataTypeConversion', modelName, 'ToInt8_s0', [660 335 720 365], ...
    'OutDataTypeStr', 'int8');
add_block_safe('DataTypeConversion', modelName, 'ToInt8_s1', [660 395 720 425], ...
    'OutDataTypeStr', 'int8');
add_block_safe('Constant', modelName, 'InValid_Soft', [660 450 720 480], ...
    'Value', '1', 'OutDataTypeStr', 'boolean');
add_block_safe('HDLCosimulation', modelName, 'Viterbi_Soft_RTL', ...
    [760 350 880 450]);
add_block_safe('ErrorRateCalculation', modelName, 'BER_Soft_RTL', ...
    [920 370 1000 410], 'WsName', 'BER_soft_rtl');

add_line(modelName, 'Soft_Sat/1',            'Buf_Soft/1',          'autorouting','on');
add_line(modelName, 'Buf_Soft/1',            'Sel_Soft_s0/1',       'autorouting','on');
add_line(modelName, 'Buf_Soft/1',            'Sel_Soft_s1/1',       'autorouting','on');
add_line(modelName, 'Sel_Soft_s0/1',         'ToInt8_s0/1',         'autorouting','on');
add_line(modelName, 'Sel_Soft_s1/1',         'ToInt8_s1/1',         'autorouting','on');
add_line(modelName, 'InValid_Soft/1',        'Viterbi_Soft_RTL/1',  'autorouting','on');
add_line(modelName, 'ToInt8_s0/1',           'Viterbi_Soft_RTL/2',  'autorouting','on');
add_line(modelName, 'ToInt8_s1/1',           'Viterbi_Soft_RTL/3',  'autorouting','on');
add_line(modelName, 'Viterbi_Soft_RTL/2',    'BER_Soft_RTL/2',      'autorouting','on');
% Same caveat as the hard cosim branch -- RTL PIPELINE=1 soft path adds
% +2 cycles on top of TB_DEPTH; tweak DelayLength if BER misaligns.
add_line(modelName, 'Tx_Delay_Soft/1',       'BER_Soft_RTL/1',      'autorouting','on');
end

% ---------------------------------------------------------------------------
function write_cosim_do_files()
% Emit ModelSim/Questa .do scripts that compile the pipelined RTL and
% start an HDL Verifier cosim server bound to the matching DUT module.
%
% Files are written next to this builder script (the simulink/ folder).
% Verilog sources live one level up in ../verilog/, so the .do scripts
% reference them with a relative path.
here = fileparts(mfilename('fullpath'));
verilogDir = fullfile(here, '..', 'verilog');

hardDo = fullfile(here, 'cosim_hard.do');
softDo = fullfile(here, 'cosim_soft.do');

hard = sprintf([ ...
    '# Auto-generated by build_viterbi_simulink_model.m\n' ...
    '# Launch with:  vsim -do cosim_hard.do\n' ...
    'if {[file exists work]} { vdel -lib work -all }\n' ...
    'vlib work\n' ...
    'vlog -sv "%s/viterbi_hard_decoder.v"\n' ...
    '# HDL Verifier cosim server: matches the HDL Cosim block in the .slx.\n' ...
    'vsim -voptargs=+acc work.viterbi_hard_decoder\n' ...
    '# Drive a free-running clock from the simulator side; Simulink only\n' ...
    '# strobes data, the cosim block synchronises sample times.\n' ...
    'force -repeat 20 ns clk 0 0 ns, 1 10 ns\n' ...
    'force rst_n 0 0 ns, 1 30 ns\n' ...
    '# Hand control to the HDL Verifier cosim socket. In the HDL Cosim\n' ...
    '# block dialog (Simulink side), set Connection method = Socket and\n' ...
    '# point it at the host/port printed by nclaunch/cosimWizard or use\n' ...
    '# matlabtb / hdlsimulink as appropriate for your release.\n' ...
    'echo "RTL compiled. Open the HDL Cosim block dialog and click\n' ...
    '      ''Generate connection'' or run cosimWizard to bind."\n'], ...
    strrep(verilogDir, '\', '/'));

soft = sprintf([ ...
    '# Auto-generated by build_viterbi_simulink_model.m\n' ...
    '# Launch with:  vsim -do cosim_soft.do\n' ...
    'if {[file exists work]} { vdel -lib work -all }\n' ...
    'vlib work\n' ...
    'vlog -sv "%s/viterbi_soft_decoder.v"\n' ...
    'vsim -voptargs=+acc work.viterbi_soft_decoder\n' ...
    'force -repeat 20 ns clk 0 0 ns, 1 10 ns\n' ...
    'force rst_n 0 0 ns, 1 30 ns\n' ...
    'echo "RTL compiled. Open the HDL Cosim block dialog and click\n' ...
    '      ''Generate connection'' or run cosimWizard to bind."\n'], ...
    strrep(verilogDir, '\', '/'));

fid = fopen(hardDo, 'w'); fwrite(fid, hard); fclose(fid);
fid = fopen(softDo, 'w'); fwrite(fid, soft); fclose(fid);
fprintf('Wrote %s\n', hardDo);
fprintf('Wrote %s\n', softDo);
end
