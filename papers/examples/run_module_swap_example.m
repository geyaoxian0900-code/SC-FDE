function results = run_module_swap_example()
%RUN_MODULE_SWAP_EXAMPLE Run SC-TDE with a replacement channel module.

papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
addpath(fullfile(papersDir, "engineering_simulation"));
addpath(fileparts(mfilename("fullpath")));

modules.channel = @custom_flat_channel;
options.makePlot = false;
options.trainingSymbols = 128;
options.dataSymbols = 300;
options.modules = modules;
results = simulate_chapter2_single_carrier_tde(options);
end
