function result = simulate_chapter6_figure615(options)
%SIMULATE_CHAPTER6_FIGURE615 Generate the Chapter 6 Fig. 6-15 result.

if nargin < 1 || isempty(options)
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter6_figure615"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter6_figure615(options, papersDir);
fprintf("Fig. 6-15 saved: %s\n", result.figurePath);
fprintf("Monte Carlo bits per curve point: DSSS-IDMA=%d, conventional CSK=%d, CSK-IDMA=%d.\n", ...
    result.bitCount(1), result.bitCount(2), result.bitCount(3));
end
