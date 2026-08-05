function results = simulate_chapter4_figure431(options)
%SIMULATE_CHAPTER4_FIGURE431 Run the paper-aligned Figure 4-31 simulation.

if nargin < 1
    options = struct();
end
rootDir = fileparts(mfilename("fullpath"));
moduleDir = fullfile(fileparts(rootDir), "modules");
if isempty(which("scfde.run_chapter4_figure431_reference"))
    addpath(moduleDir);
end
if ~isfield(options, "outputDir")
    options.outputDir = fullfile(rootDir, "results");
end
options.berMetric = "uncoded";
options.figureBaseName = "fig4_31_ted_teq_uncoded_ber";
results = scfde.run_chapter4_figure431_reference(options, rootDir);
end
