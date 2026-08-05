function result = simulate_chapter5_figure528(options)
%SIMULATE_CHAPTER5_FIGURE528 Reproduce the UWA CCK receiver FER comparison.

if nargin < 1
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter5_figure528"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter5_figure528(options, papersDir);
end
