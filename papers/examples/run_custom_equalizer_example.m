function example = run_custom_equalizer_example()
%RUN_CUSTOM_EQUALIZER_EXAMPLE Demonstrate plug-and-play equalizer modules.
% Runs the SC-TDE pipeline three ways with the same settings:
%   1. "all"              - every built-in equalizer
%   2. ID string array    - selected built-ins
%   3. function handle    - a custom matched-filter equalizer
%   4. cell array         - mix of a custom module and a built-in ID

papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
addpath(fullfile(papersDir, "engineering_simulation"));
addpath(fullfile(papersDir, "examples"));

cfg = struct("makePlot", false, "trainingSymbols", 64, ...
    "dataSymbols", 120, "feedforwardTaps", 12, "feedbackTaps", 6, ...
    "snrDb", 12, "dopplerHz", 1.5, "symbolRate", 4000, ...
    "pathDelays", [0, 2, 5, 8], ...
    "pathGains", [1, 0.72 * exp(1j * 0.5), 0.48 * exp(-1j * 1.0), ...
    0.30 * exp(1j * 1.7)], ...
    "numSubbands", 4, "ptrRegularization", 0.02, ...
    "lmsStep", 0.008, "nlmsStep", 0.35, ...
    "rlsForgettingFactor", 0.985, "rlsInitialInverseCorrelation", 100, ...
    "dpllProportionalGain", 0.020, "dpllIntegralGain", 0.0004);

example.all = run_with(cfg, "all");
example.selected = run_with(cfg, ["dfe", "nlms-dfe", "ptr-dfe"]);
example.custom = run_with(cfg, @custom_matched_filter);
example.mixed = run_with(cfg, { @custom_matched_filter, "rls-dfe" });

fprintf("Built-in 'all'   : %d equalizers\n", numel(example.all.receiver.ids));
fprintf("Selected IDs     : %s\n", strjoin(example.selected.receiver.ids, ", "));
fprintf("Custom handle    : %s\n", example.custom.receiver.ids);
fprintf("Mixed cell       : %s\n", strjoin(example.mixed.receiver.ids, ", "));
fprintf("Custom matched-filter BER = %.4f\n", example.custom.metrics.ber);
end

function result = run_with(cfg, equalizers)
cfg.equalizers = equalizers;
modules = scfde.default_modules();
result = scfde.run_pipeline(cfg, modules);
end
