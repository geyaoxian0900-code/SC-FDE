function result = simulate_chapter6_figure601(options)
%SIMULATE_CHAPTER6_FIGURE601 Generate the Chapter 6 Fig. 6-1 result.

if nargin < 1 || isempty(options)
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter6_figure601"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter6_figure601(options, papersDir);
fprintf("Fig. 6-1 saved: %s\n", result.figurePath);
fprintf("Cyclic shift: %d chips; estimated shift: %d chips.\n", ...
    result.config.shiftChips, result.estimatedShiftChips);
end
