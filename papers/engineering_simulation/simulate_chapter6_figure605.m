function result = simulate_chapter6_figure605(options)
%SIMULATE_CHAPTER6_FIGURE605 Generate the Chapter 6 Fig. 6-5 CIR result.

if nargin < 1 || isempty(options)
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter6_figure605"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter6_figure605(options, papersDir);
fprintf("Fig. 6-5 saved: %s\n", result.figurePath);
fprintf("Four-element CIR: %d complex taps over %.1f ms.\n", ...
    size(result.tapTable, 1), max(result.tapTable(:, 2)));
end
