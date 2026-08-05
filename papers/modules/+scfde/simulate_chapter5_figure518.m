function result = simulate_chapter5_figure518(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE518 Reproduce the GCCK-8PSK-12R receiver comparison.
if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
defaults.snrList = 0:1:14;
defaults.snrDb = 8;
defaults.symbols = 128;
defaults.frameCount = 30;
defaults.randomSeed = 20260803;
defaults.groups = "gcck";
defaults.gcckModes = "GCCK-8PSK-12R";
defaults.receiverMethods = "all";
defaults.dynamicAlphas = 1;
defaults.gcckChannel = [0.76 0 0 0.55 0 0 0 0 0 0 0.38];
defaults.receiverSnrDefinition = "EbN0";
defaults.receiverCandidateLimit = 4096;
defaults.useCyclicPrefix = false;
defaults.skipDiagnostics = true;
defaults.makePlot = false;
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options_local(defaults, options);
cfg.isiModulation = "GCCK-8PSK-12R";
cfg.isiChannel = cfg.gcckChannel;
cfg.isiMethods = "all";
cfg.runAwgn = false;
cfg.runIsi = true;
cfg.runTurbo = false;
cfg.normalizeIsiChannel = false;
cfg.isiReceiverProfile = "gcckFigure517";
cfg.receiverBranchCount = 2;
cfg.makePlot = false;
result = scfde.run_chapter5_cck_suite_impl(cfg, simulationDir);
result.plotBer = result.isiBer;
for methodIndex = 1:size(result.plotBer, 1)
    zeroMask = result.plotBer(methodIndex, :) == 0;
    result.plotBer(methodIndex, zeroMask) = 3 ./ result.isiBitTotals(zeroMask);
end

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, "fig5_18_gcck_8psk_12r_receivers.png");
matPath = fullfile(cfg.outputDir, "fig5_18_gcck_8psk_12r_receivers.mat");
csvPath = fullfile(cfg.outputDir, "fig5_18_gcck_8psk_12r_receivers.csv");

fig = figure("Color", "w", "Position", [120 80 760 560], "Visible", "off");
ax = axes(fig); hold(ax, "on");
styles = {"o-", "s-", "^-", "d-", "x-", "+-"};
for index = 1:numel(result.isiMethodNames)
    semilogy(ax, result.snrList, result.plotBer(index, :), styles{index}, ...
        "LineWidth", 1.15, "MarkerSize", 5, ...
        "DisplayName", result.isiMethodNames(index));
end
grid(ax, "on"); ax.GridAlpha = 0.25; ax.YScale = "log";
xlim(ax, [0 14]); ylim(ax, [1e-6 1]);
xlabel(ax, "信噪比 SNR (dB)"); ylabel(ax, "误码率 BER");
title(ax, "图5-18 GCCK-8PSK-12R 在 3 km 水声信道中的接收机性能比较");
legend(ax, "Location", "southwest");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, figurePath, "Resolution", 220); close(fig);

snrValues = result.snrList(:);
berValues = result.isiBer.';
errorCounts = result.isiErrorCounts.';
bitTotals = result.isiBitTotals(:);
methodNames = matlab.lang.makeValidName("BER_" + result.isiMethodNames);
errorNames = matlab.lang.makeValidName("Errors_" + result.isiMethodNames);
tableNames = ["SNR_dB", methodNames, errorNames, "BitTotal"];
resultTable = array2table([snrValues, berValues, errorCounts, bitTotals], ...
    "VariableNames", cellstr(tableNames));
writetable(resultTable, csvPath);
result.figurePath = figurePath;
result.matPath = matPath;
result.csvPath = csvPath;
save(matPath, "result", "cfg");
end

function output = merge_options_local(defaults, options)
output = defaults;
names = fieldnames(options);
for index = 1:numel(names)
    output.(names{index}) = options.(names{index});
end
end
