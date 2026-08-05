function result = simulate_chapter6_figure613(options)
%SIMULATE_CHAPTER6_FIGURE613 Generate the Chapter 6 Fig. 6-13 result.

if nargin < 1 || isempty(options)
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter6_figure613"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter6_figure613(options, papersDir);
fprintf("Fig. 6-13 saved: %s\n", result.figurePath);
fprintf("Monte Carlo bits per curve point: %d\n", result.bitCount(1));
end
