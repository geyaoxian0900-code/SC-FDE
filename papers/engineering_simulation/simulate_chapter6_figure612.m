function result = simulate_chapter6_figure612(options)
%SIMULATE_CHAPTER6_FIGURE612 Generate the Chapter 6 Fig. 6-12 result.

if nargin < 1 || isempty(options)
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter6_figure612"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter6_figure612(options, papersDir);
fprintf("Fig. 6-12 saved: %s\n", result.figurePath);
fprintf("Monte Carlo sample count: %d bits per curve point.\n", result.config.bitsPerPoint);
end
