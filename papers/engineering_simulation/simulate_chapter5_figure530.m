function result = simulate_chapter5_figure530(options)
%SIMULATE_CHAPTER5_FIGURE530 Run the modular Figure 5-30 simulation.

if nargin < 1
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.simulate_chapter5_figure530"))
    addpath(moduleDir);
end
result = scfde.simulate_chapter5_figure530(options, papersDir);
end
