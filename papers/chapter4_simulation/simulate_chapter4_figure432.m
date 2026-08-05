function results = simulate_chapter4_figure432(options)
%SIMULATE_CHAPTER4_FIGURE432 Run the coded BER simulation for Figure 4-32.

if nargin < 1
    options = struct();
end
rootDir = fileparts(mfilename("fullpath"));
moduleDir = fullfile(fileparts(rootDir), "modules");
if isempty(which("scfde.run_chapter4_figure431_reference"))
    addpath(moduleDir);
end
options.berMetric = "coded";
options.channelEstimateMode = "perfect";
options.figureBaseName = "fig4_32_fdda_teq_coded_ber";
if ~isfield(options, "outputDir")
    options.outputDir = fullfile(rootDir, "results");
end
results = scfde.run_chapter4_figure431_reference(options, rootDir);
end
