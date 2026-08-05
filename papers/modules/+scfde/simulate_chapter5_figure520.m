function result = simulate_chapter5_figure520(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE520 Compare TR-Diversity in static and quasi-static fading.
if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrList = 0:2:18;
defaults.symbols = [128, 128, 56];
defaults.frameCount = [64, 48, 32];
defaults.quasiRealizations = [16, 12, 8];
defaults.quasiCorrelation = 0.995;
defaults.randomSeed = 20260805;
defaults.channel = [0.76 0 0 0.55 0 0 0 0 0 0 0.38];
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options_local(defaults, options);

modeNames = ["GCCK-QPSK-4R", "GCCK-QPSK-8R", "GCCK-8PSK-12R"];
scenarioNames = ["静止信道", "准静止衰落信道"];
modeCount = numel(modeNames);
scenarioCount = numel(scenarioNames);
snrCount = numel(cfg.snrList);
errorCounts = zeros(modeCount, scenarioCount, snrCount);
bitTotals = zeros(modeCount, scenarioCount, snrCount);

for modeIndex = 1:modeCount
    staticResult = run_receiver(modeNames(modeIndex), cfg.snrList, ...
        cfg.frameCount(modeIndex), cfg.symbols(modeIndex), cfg.channel, ...
        cfg.channel, cfg.randomSeed + 100000 * modeIndex, simulationDir);
    errorCounts(modeIndex, 1, :) = reshape(staticResult.isiErrorCounts, 1, 1, []);
    bitTotals(modeIndex, 1, :) = reshape(staticResult.isiBitTotals, 1, 1, []);

    framesPerRealization = cfg.frameCount(modeIndex) / cfg.quasiRealizations(modeIndex);
    assert(mod(framesPerRealization, 1) == 0, "SCFDE:Figure520FrameCount", ...
        "frameCount must be divisible by quasiRealizations for every modulation.");
    quasiChannels = complex(zeros(cfg.quasiRealizations(modeIndex), ...
        numel(cfg.channel)));
    quasiChannel = cfg.channel;
    for realizationIndex = 1:cfg.quasiRealizations(modeIndex)
        rng(cfg.randomSeed + 300000 * modeIndex + realizationIndex, "twister");
        quasiChannel = next_quasi_static_channel(quasiChannel, cfg.channel, ...
            cfg.quasiCorrelation);
        quasiChannels(realizationIndex, :) = quasiChannel;
    end
    for snrIndex = 1:snrCount
        for realizationIndex = 1:cfg.quasiRealizations(modeIndex)
            local = run_receiver(modeNames(modeIndex), cfg.snrList(snrIndex), ...
                framesPerRealization, cfg.symbols(modeIndex), ...
                quasiChannels(realizationIndex, :), ...
                cfg.channel, cfg.randomSeed + 200000 * modeIndex + ...
                1000 * snrIndex + realizationIndex, simulationDir);
            errorCounts(modeIndex, 2, snrIndex) = ...
                errorCounts(modeIndex, 2, snrIndex) + local.isiErrorCounts;
            bitTotals(modeIndex, 2, snrIndex) = ...
                bitTotals(modeIndex, 2, snrIndex) + local.isiBitTotals;
        end
    end
end

ber = errorCounts ./ bitTotals;
plotBer = ber;
zeroMask = plotBer == 0;
plotBer(zeroMask) = 3 ./ bitTotals(zeroMask);
result.config = cfg;
result.modeNames = modeNames;
result.scenarioNames = scenarioNames;
result.snrList = cfg.snrList;
result.ber = ber;
result.plotBer = plotBer;
result.errorCounts = errorCounts;
result.bitTotals = bitTotals;

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, "fig5_20_tr_diversity_static_quasistatic.png");
matPath = fullfile(cfg.outputDir, "fig5_20_tr_diversity_static_quasistatic.mat");
csvPath = fullfile(cfg.outputDir, "fig5_20_tr_diversity_static_quasistatic.csv");
fig = figure("Color", "w", "Position", [120 80 820 610], "Visible", "off");
ax = axes(fig); hold(ax, "on");
colors = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.49 0.18 0.56];
markers = {"o", "s", "^"};
for modeIndex = 1:modeCount
    for scenarioIndex = 1:scenarioCount
        if scenarioIndex == 1
            lineStyle = "-";
        else
            lineStyle = "--";
        end
        semilogy(ax, cfg.snrList, ...
            squeeze(plotBer(modeIndex, scenarioIndex, :)).', ...
            "Color", colors(modeIndex, :), "LineStyle", lineStyle, ...
            "Marker", markers{modeIndex}, "LineWidth", 1.25, ...
            "MarkerSize", 5.5, "DisplayName", ...
            scenarioNames(scenarioIndex) + "，" + modeNames(modeIndex));
    end
end
grid(ax, "on"); ax.GridAlpha = 0.32; ax.GridLineStyle = "--"; ax.YScale = "log";
xlim(ax, [0 18]); ylim(ax, [1e-4 1]); xticks(ax, 0:2:18);
xlabel(ax, "信噪比/dB"); ylabel(ax, "误码率 BER");
title(ax, "图5-20 静止及准静止衰落信道中 TR-Diversity（2次迭代）GCCK 接收机性能比较");
legend(ax, "Location", "southwest");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei", "FontSize", 10);
exportgraphics(fig, figurePath, "Resolution", 220); close(fig);

modeColumn = strings(0, 1);
scenarioColumn = strings(0, 1);
snrColumn = zeros(0, 1);
berColumn = zeros(0, 1);
errorColumn = zeros(0, 1);
bitColumn = zeros(0, 1);
for modeIndex = 1:modeCount
    for scenarioIndex = 1:scenarioCount
        modeColumn = [modeColumn; repmat(modeNames(modeIndex), snrCount, 1)];
        scenarioColumn = [scenarioColumn; repmat(scenarioNames(scenarioIndex), snrCount, 1)];
        snrColumn = [snrColumn; cfg.snrList(:)];
        berColumn = [berColumn; squeeze(ber(modeIndex, scenarioIndex, :))];
        errorColumn = [errorColumn; squeeze(errorCounts(modeIndex, scenarioIndex, :))];
        bitColumn = [bitColumn; squeeze(bitTotals(modeIndex, scenarioIndex, :))];
    end
end
writetable(table(modeColumn, scenarioColumn, snrColumn, berColumn, errorColumn, ...
    bitColumn, 'VariableNames', {'Modulation', 'ChannelScenario', 'SNR_dB', ...
    'BER', 'ErrorCount', 'BitTotal'}), csvPath);
result.figurePath = figurePath;
result.matPath = matPath;
result.csvPath = csvPath;
save(matPath, "result", "cfg");
end

function result = run_receiver(modeName, snrList, frameCount, symbols, ...
        transmitChannel, receiverChannel, randomSeed, simulationDir)
result = scfde.run_chapter5_cck_suite_impl(struct( ...
    "snrList", snrList, ...
    "symbols", symbols, ...
    "frameCount", frameCount, ...
    "randomSeed", randomSeed, ...
    "isiModulation", modeName, ...
    "isiMethods", "TR-Diversity (2 iterations)", ...
    "isiReceiverProfile", "gcckFigure517", ...
    "isiChannel", transmitChannel, ...
    "receiverChannel", receiverChannel, ...
    "receiverBranchCount", 2, ...
    "receiverSnrDefinition", "EbN0", ...
    "normalizeIsiChannel", false, ...
    "runAwgn", false, ...
    "runIsi", true, ...
    "runTurbo", false, ...
    "skipDiagnostics", true, ...
    "fastTrDiversity2", true, ...
    "makePlot", false), simulationDir);
end

function channel = next_quasi_static_channel(previous, reference, correlation)
active = abs(reference) > 0;
innovation = complex(zeros(size(reference)));
innovation(active) = abs(reference(active)) .* ...
    (randn(1, sum(active)) + 1j * randn(1, sum(active))) / sqrt(2);
channel = correlation * previous + sqrt(1 - correlation^2) * innovation;
channel(~active) = 0;
end

function output = merge_options_local(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
