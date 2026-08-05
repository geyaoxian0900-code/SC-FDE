function result = simulate_chapter5_figure529(options)
%SIMULATE_CHAPTER5_FIGURE529 Run the modular Figure 5-29 simulation.

if nargin < 1
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter5_figure529"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter5_figure529(options, papersDir);
end
