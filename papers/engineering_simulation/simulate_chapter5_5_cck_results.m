function results = simulate_chapter5_5_cck_results(options)
%SIMULATE_CHAPTER5_5_CCK_RESULTS Reproduce the Chapter 5.5 CCK studies.

if nargin < 1
    options = struct();
end
papersDir = fileparts(fileparts(mfilename("fullpath")));
moduleDir = fullfile(papersDir, "modules");
if isempty(which("scfde.run_chapter5_5_cck_suite"))
    addpath(moduleDir);
end
results = scfde.run_chapter5_5_cck_suite(options, fileparts(mfilename("fullpath")));
end
