function result = simulate_chapter5_figure527(options)
%SIMULATE_CHAPTER5_FIGURE527 Reproduce the UWA CCK receiver comparison.

if nargin < 1
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter5_figure527"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter5_figure527(options, papersDir);
end
