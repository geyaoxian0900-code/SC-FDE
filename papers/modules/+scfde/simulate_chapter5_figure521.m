function result = simulate_chapter5_figure521(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE521 Evaluate TR-Diversity under AR time-varying channels.
if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrList = 0:1:20;
defaults.symbols = 50;
defaults.frameCount = [64, 64, 32];
defaults.channelCorrelation = [1, 0.9999, 0.9995, 0.999];
defaults.timeVaryingInnovationScale = 0.15;
defaults.randomSeed = 20260806;
defaults.channel = [0.76 0 0 0.55 0 0 0 0 0 0 0.38];
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options_local(defaults, options);

modeNames = ["GCCK-QPSK-4R", "GCCK-QPSK-8R", "GCCK-8PSK-12R"];
panelLabels = ["(a) GCCK-QPSK-4R", "(b) GCCK-QPSK-8R", ...
    "(c) GCCK-8PSK-12R"];
conditionLabels = ["时不变信道", "\alpha=0.9999", ...
    "\alpha=0.9995", "\alpha=0.999"];
modeCount = numel(modeNames);
conditionCount = numel(conditionLabels);
snrCount = numel(cfg.snrList);
errorCounts = zeros(modeCount, conditionCount, snrCount);
bitTotals = zeros(modeCount, conditionCount, snrCount);

for modeIndex = 1:modeCount
    for conditionIndex = 1:conditionCount
        seed = cfg.randomSeed + 100000 * modeIndex + 1000 * conditionIndex;
        for snrIndex = 1:snrCount
            local = run_receiver(modeNames(modeIndex), cfg.snrList(snrIndex), ...
                cfg.frameCount(modeIndex), cfg.symbols, cfg.channel, ...
                cfg.channelCorrelation(conditionIndex), cfg.timeVaryingInnovationScale, ...
                seed, simulationDir);
            errorCounts(modeIndex, conditionIndex, snrIndex) = local.isiErrorCounts;
            bitTotals(modeIndex, conditionIndex, snrIndex) = local.isiBitTotals;
        end
    end
end

ber = errorCounts ./ bitTotals;
plotBer = ber;
for modeIndex = 1:modeCount
    for conditionIndex = 1:conditionCount
        firstZero = find(errorCounts(modeIndex, conditionIndex, :) == 0, 1);
        if ~isempty(firstZero)
            plotBer(modeIndex, conditionIndex, firstZero:end) = nan;
        end
    end
end
result.config = cfg;
result.modeNames = modeNames;
result.conditionLabels = conditionLabels;
result.snrList = cfg.snrList;
result.ber = ber;
result.plotBer = plotBer;
result.errorCounts = errorCounts;
result.bitTotals = bitTotals;

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, "fig5_21_time_variation_tr_diversity.png");
matPath = fullfile(cfg.outputDir, "fig5_21_time_variation_tr_diversity.mat");
csvPath = fullfile(cfg.outputDir, "fig5_21_time_variation_tr_diversity.csv");
fig = figure("Color", "w", "Position", [100 55 1160 890], "Visible", "off");
axesPosition = {[0.09 0.61 0.37 0.31], [0.59 0.61 0.37 0.31], ...
    [0.34 0.17 0.37 0.31]};
colors = [0.18 0.55 0.34; 0.00 0.45 0.74; 0.85 0.33 0.10; 0.49 0.18 0.56];
markers = {"none", "s", "d", "o"};
lineStyles = {"-", "-", "-", "-"};
for modeIndex = 1:modeCount
    ax = axes(fig, "Position", axesPosition{modeIndex}); hold(ax, "on");
    for conditionIndex = 1:conditionCount
        semilogy(ax, cfg.snrList, ...
            squeeze(plotBer(modeIndex, conditionIndex, :)).', ...
            "Color", colors(conditionIndex, :), ...
            "LineStyle", lineStyles{conditionIndex}, ...
            "Marker", markers{conditionIndex}, "LineWidth", 1.2, ...
            "MarkerSize", 5.2, "DisplayName", conditionLabels(conditionIndex));
    end
    grid(ax, "on"); ax.GridAlpha = 0.32; ax.GridLineStyle = "--"; ax.YScale = "log";
    xlim(ax, [0 20]); ylim(ax, [2e-5 1]); xticks(ax, 0:2:20);
    xlabel(ax, {"信噪比/dB", panelLabels(modeIndex)});
    ylabel(ax, "误码率");
    legend(ax, "Location", "northeast", "Interpreter", "tex");
end
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei", "FontSize", 10);
annotation(fig, "textbox", [0.20 0.045 0.60 0.045], "String", ...
    "图5-21 信道时变对 TR-Diversity（2次迭代）接收机的影响", ...
    "EdgeColor", "none", "HorizontalAlignment", "center", ...
    "FontName", "Microsoft YaHei", "FontSize", 13);
exportgraphics(fig, figurePath, "Resolution", 220); close(fig);

modeColumn = strings(0, 1);
conditionColumn = strings(0, 1);
snrColumn = zeros(0, 1);
berColumn = zeros(0, 1);
errorColumn = zeros(0, 1);
bitColumn = zeros(0, 1);
for modeIndex = 1:modeCount
    for conditionIndex = 1:conditionCount
        modeColumn = [modeColumn; repmat(modeNames(modeIndex), snrCount, 1)];
        conditionColumn = [conditionColumn; repmat(conditionLabels(conditionIndex), snrCount, 1)];
        snrColumn = [snrColumn; cfg.snrList(:)];
        berColumn = [berColumn; squeeze(ber(modeIndex, conditionIndex, :))];
        errorColumn = [errorColumn; squeeze(errorCounts(modeIndex, conditionIndex, :))];
        bitColumn = [bitColumn; squeeze(bitTotals(modeIndex, conditionIndex, :))];
    end
end
writetable(table(modeColumn, conditionColumn, snrColumn, berColumn, errorColumn, ...
    bitColumn, 'VariableNames', {'Modulation', 'ChannelCorrelation', 'SNR_dB', ...
    'BER', 'ErrorCount', 'BitTotal'}), csvPath);
result.figurePath = figurePath;
result.matPath = matPath;
result.csvPath = csvPath;
save(matPath, "result", "cfg");
end

function result = run_receiver(modeName, snrList, frameCount, symbols, ...
        channel, timeVaryingCorrelation, innovationScale, randomSeed, simulationDir)
result = scfde.run_chapter5_cck_suite_impl(struct( ...
    "snrList", snrList, ...
    "symbols", symbols, ...
    "frameCount", frameCount, ...
    "randomSeed", randomSeed, ...
    "isiModulation", modeName, ...
    "isiMethods", "TR-Diversity (2 iterations)", ...
    "isiReceiverProfile", "gcckFigure517", ...
    "isiChannel", channel, ...
    "receiverChannel", channel, ...
    "receiverBranchCount", 2, ...
    "receiverSnrDefinition", "EbN0", ...
    "normalizeIsiChannel", false, ...
    "timeVaryingCorrelation", timeVaryingCorrelation, ...
    "timeVaryingInnovationScale", innovationScale, ...
    "runAwgn", false, ...
    "runIsi", true, ...
    "runTurbo", false, ...
    "skipDiagnostics", true, ...
    "fastTrDiversity2", true, ...
    "makePlot", false), simulationDir);
end

function output = merge_options_local(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
