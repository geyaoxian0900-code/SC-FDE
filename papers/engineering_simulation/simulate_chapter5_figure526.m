function result = simulate_chapter5_figure526(options)
%SIMULATE_CHAPTER5_FIGURE526 Reproduce Figure 5-26 with the UWA CCK/DSSS model.

if nargin < 1
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter5_figure526"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter5_figure526(options, papersDir);
end
