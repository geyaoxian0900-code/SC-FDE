function result = simulate_chapter6_figure606(options)
%SIMULATE_CHAPTER6_FIGURE606 Generate the Chapter 6 Fig. 6-6 result.

if nargin < 1 || isempty(options)
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter6_figure606"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter6_figure606(options, papersDir);
fprintf("Fig. 6-6 saved: %s\n", result.figurePath);
fprintf("Four users, %d frames per SNR, %d bits per curve point.\n", ...
    result.config.frameCount, result.bitCount(1, 1));
end
