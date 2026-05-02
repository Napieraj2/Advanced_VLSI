function export_simulink_model_image(varargin)
% EXPORT_SIMULINK_MODEL_IMAGE  Render Viterbi_Simulink_Model.slx to PNG.
%
%   export_simulink_model_image()                    % default 150 DPI
%   export_simulink_model_image('Resolution', 200)
%   export_simulink_model_image('Model', 'Viterbi_Simulink_Model')
%
% Writes plots/simulink_model.png next to this script. Used by the
% "Simulink Cross-Check" section of the top-level README.

p = inputParser;
addParameter(p, 'Model',      'Viterbi_Simulink_Model', @ischar);
addParameter(p, 'Resolution', 150, @(x) isnumeric(x) && isscalar(x));
parse(p, varargin{:});
modelName  = p.Results.Model;
resolution = p.Results.Resolution;

if ~bdIsLoaded(modelName)
    if exist([modelName '.slx'], 'file')
        load_system(modelName);
    else
        error('Model %s.slx not found. Run build_viterbi_simulink_model first.', modelName);
    end
end

here    = fileparts(mfilename('fullpath'));
plotDir = fullfile(here, 'plots');
if ~exist(plotDir, 'dir'); mkdir(plotDir); end
pngPath = fullfile(plotDir, 'simulink_model.png');

% print uses '-s<modelName>' to refer to a Simulink system; -dpng PNG output.
print(['-s' modelName], '-dpng', sprintf('-r%d', resolution), pngPath);
fprintf('Wrote %s\n', pngPath);
end
