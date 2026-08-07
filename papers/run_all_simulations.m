function summary = run_all_simulations(options)
%RUN_ALL_SIMULATIONS Unified runner for paper and engineering simulations.
%   SUMMARY = RUN_ALL_SIMULATIONS(OPTIONS) executes selected experiment IDs.
%   Use LIST_SIMULATIONS to inspect IDs. The default profile is "quick".

if nargin < 1
    options = struct();
end
rootDir = fileparts(mfilename("fullpath"));
add_simulation_paths(rootDir);

defaults.profile = "quick";
defaults.experiments = "all";
defaults.makePlot = true;
defaults.stopOnError = false;
defaults.modules = struct();
defaults.experimentOptions = struct();
cfg = scfde.merge_struct(defaults, options);
assert(any(string(cfg.profile) == ["quick", "full"]), ...
    "Profile must be 'quick' or 'full'.");

registry = simulation_registry();
selected = select_experiments(registry, cfg.experiments);
summary.profile = string(cfg.profile);
summary.startedAt = datetime("now");
summary.entries = struct("id", {}, "status", {}, "elapsedSeconds", {}, ...
    "outputPath", {}, "message", {});

fprintf("\n===== Unified underwater acoustic simulation runner (%s) =====\n", ...
    summary.profile);
for experimentIndex = selected
    item = registry(experimentIndex);
    started = tic;
    entry.id = item.id;
    entry.status = "FAIL";
    entry.outputPath = "";
    entry.message = "";
    try
        experimentOptions = profile_options(item.id, cfg);
        result = item.run(experimentOptions);
        entry.status = "PASS";
        entry.outputPath = result_output_path(result);
    catch exception
        entry.message = string(exception.message);
        if cfg.stopOnError
            rethrow(exception);
        end
    end
    entry.elapsedSeconds = toc(started);
    summary.entries(end + 1) = entry; %#ok<AGROW>
    fprintf("%-32s %s (%.2f s)\n", ...
        entry.id, entry.status, entry.elapsedSeconds);
end

summary.completedAt = datetime("now");
resultDir = fullfile(rootDir, "results");
if ~exist(resultDir, "dir")
    mkdir(resultDir);
end
summary.summaryPath = fullfile(resultDir, "all_simulations_summary.mat");
save(summary.summaryPath, "summary");
fprintf("Summary: %s\n", summary.summaryPath);
end

function registry = simulation_registry()
definitions = {
    "paper.chapter2", "Paper UW and SC-FDE", @run_chapter2_simulation
    "paper.chapter3", "Paper synchronization and Doppler", @run_chapter3_simulation
    "paper.chapter4", "Paper decision-feedback equalization", @run_chapter4_simulation
    "engineering.sc_tde", "Engineering single-carrier TDE", @simulate_chapter2_single_carrier_tde
    "engineering.sc_tde_paper", "Paper-parameter Bellhop SC-TDE reproduction", @reproduce_chapter2_sc_tde_paper
    "engineering.sc_fde", "Engineering SC-FDE", @simulate_chapter3_scfde
    "engineering.iterative", "Engineering iterative equalization", @simulate_chapter4_iterative_equalization
    "engineering.cck", "Engineering CCK", @simulate_chapter5_cck
    "engineering.cck_5_5", "Chapter 5.5 GCCK, Turbo, and CCK-SM", @simulate_chapter5_5_cck_results
    "engineering.csk", "Engineering CSK and multiuser", @simulate_chapter6_csk_multiuser
    "engineering.text", "Engineering text end-to-end link", @run_text_experiment
    };
registry = struct("id", definitions(:, 1), ...
    "description", definitions(:, 2), "run", definitions(:, 3));
end

function selected = select_experiments(registry, requested)
requested = string(requested);
allIds = string({registry.id});
if isscalar(requested) && requested == "all"
    selected = 1:numel(registry);
    return;
end
unknown = setdiff(requested, allIds);
assert(isempty(unknown), "Unknown simulation ID: %s", strjoin(unknown, ", "));
selected = find(ismember(allIds, requested));
end

function options = profile_options(id, cfg)
options = struct("makePlot", cfg.makePlot);
if string(cfg.profile) == "quick"
    switch id
        case "paper.chapter2"
            options.mseTrials = 20;
            options.structureSnrDb = [-2, 7, 16];
            options.sequenceSnrDb = [-2, 10, 22];
            options.berSnrDb = [3, 9, 15];
            options.berTargetErrors = 20;
            options.berMaxBits = 2e4;
            options.berBlocksPerBatch = 10;
        case "paper.chapter3"
            options.monteCarloTrials = 80;
            options.fig35Trials = 3;
            options.snrLambda = [-4, 4, 12];
            options.lambdas = [1, 4, 8];
            options.snrAwgn = [-12, -2, 8];
            options.snrMultipath = [0, 10, 20];
            options.velocities = [1, 2.5, 4];
            options.snrBer = [-3, 0, 3];
        case "paper.chapter4"
            options.uncodedSnrDb = [3, 8, 13];
            options.codedSnrDb = [-2, 1, 4];
            options.uncodedMaxBits = 2e4;
            options.uncodedTargetErrors = 25;
            options.codedBlocks = 5;
        case "engineering.sc_tde"
            options.trainingSymbols = 128;
            options.dataSymbols = 500;
        case "engineering.sc_tde_paper"
            options.snrDb = [0, 6, 12];
            options.dataSymbols = 1500;
            options.trials = 2;
            options.trainingSymbols = 1500;
        case "engineering.sc_fde"
            options.frameCount = 5;
            options.snrList = [4, 10, 16];
        case "engineering.iterative"
            options.frameCount = 2;
            options.infoBits = 48;
            options.snrList = [-6, -2, 2];
        case "engineering.cck"
            options.frameCount = 2;
            options.symbols = 40;
            options.snrList = [0, 6, 12];
            options.snrDb = 6;
        case "engineering.cck_5_5"
            options.frameCount = 1;
            options.symbols = 12;
            options.snrList = [0, 6, 12];
            options.snrDb = 6;
            options.receiverCandidateLimit = 64;
        case "engineering.csk"
            options.frameCount = 2;
            options.symbolsPerFrame = 40;
            options.snrDb = [-4, 4, 12];
        case "engineering.text"
            options.inputText = "Unified SC-FDE simulation";
    end
end
if id == "engineering.sc_tde"
    options.modules = cfg.modules;
end
key = matlab.lang.makeValidName(strrep(id, ".", "_"));
if isfield(cfg.experimentOptions, key)
    options = scfde.merge_struct(options, cfg.experimentOptions.(key));
end
end

function outputPath = result_output_path(result)
outputPath = "";
if isstruct(result) && isfield(result, "outputPath")
    outputPath = string(result.outputPath);
elseif isstruct(result) && isfield(result, "figurePath")
    outputPath = string(result.figurePath);
elseif isstruct(result) && isfield(result, "outputDir")
    outputPath = string(result.outputDir);
end
end

function result = run_text_experiment(options)
inputText = "Unified SC-FDE simulation";
if isfield(options, "inputText")
    inputText = string(options.inputText);
    options = rmfield(options, "inputText");
end
result = run_text_scfde_demo(inputText, options);
end

function add_simulation_paths(rootDir)
addpath(fullfile(rootDir, "modules"));
addpath(fullfile(rootDir, "common"));
addpath(fullfile(rootDir, "chapter2_simulation"));
addpath(fullfile(rootDir, "chapter3_simulation"));
addpath(fullfile(rootDir, "chapter4_simulation"));
addpath(fullfile(rootDir, "engineering_simulation"));
end
