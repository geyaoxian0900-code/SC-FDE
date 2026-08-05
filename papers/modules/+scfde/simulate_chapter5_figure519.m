function result = simulate_chapter5_figure519(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE519 Compare GCCK performance under CIR estimation errors.
if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end
defaults.snrList = 0:1:16;
defaults.symbols = [256, 256, 96];
defaults.frameCount = [16, 16, 12];
defaults.estimationRealizations = [6, 6, 6];
defaults.estimationErrorDb = [-5, -10, -15, -20];
defaults.randomSeed = 20260804;
defaults.channel = [0.76 0 0 0.55 0 0 0 0 0 0 0.38];
defaults.modeSnrMaximum = [10, 10, 16];
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options_local(defaults, options);
modeNames = ["GCCK-QPSK-4R", "GCCK-QPSK-8R", "GCCK-8PSK-12R"];
panelLabels = ["(a) GCCK-QPSK-4R", "(b) GCCK-QPSK-8R", ...
    "(c) GCCK-8PSK-12R"];
curveLabels = ["\sigma_e^2=-5 dB", "\sigma_e^2=-10 dB", ...
    "\sigma_e^2=-15 dB", "\sigma_e^2=-20 dB", "CIR已知"];
curveCount = numel(curveLabels);
snrCount = numel(cfg.snrList);
errorCounts = zeros(numel(modeNames), curveCount, snrCount);
bitTotals = zeros(numel(modeNames), curveCount, snrCount);
activeSnr = false(numel(modeNames), snrCount);
channelPower = mean(abs(cfg.channel).^2);

for modeIndex = 1:numel(modeNames)
    activeIndices = cfg.snrList <= cfg.modeSnrMaximum(modeIndex);
    activeSnr(modeIndex, activeIndices) = true;
    modeSnrList = cfg.snrList(activeIndices);
    for curveIndex = 1:curveCount
        for realizationIndex = 1:cfg.estimationRealizations(modeIndex)
            seed = cfg.randomSeed + 10000 * modeIndex + 1000 * curveIndex + realizationIndex;
            if curveIndex <= numel(cfg.estimationErrorDb)
                rng(seed, "twister");
                errorVariance = channelPower * 10^(cfg.estimationErrorDb(curveIndex) / 10);
                channelEstimate = cfg.channel + sqrt(errorVariance / 2) * ...
                    (randn(size(cfg.channel)) + 1j * randn(size(cfg.channel)));
            else
                channelEstimate = cfg.channel;
            end
            local = scfde.run_chapter5_cck_suite_impl(struct( ...
                "snrList", modeSnrList, ...
                "symbols", cfg.symbols(modeIndex), ...
                "frameCount", cfg.frameCount(modeIndex), ...
                "randomSeed", seed + 50000, ...
                "isiModulation", modeNames(modeIndex), ...
                "isiMethods", "DFE", ...
                "isiChannel", cfg.channel, ...
                "receiverChannel", channelEstimate, ...
                "receiverSnrDefinition", "EbN0", ...
                "normalizeIsiChannel", false, ...
                "runAwgn", false, ...
                "runIsi", true, ...
                "runTurbo", false, ...
                "skipDiagnostics", true, ...
                "fastSingleDfe", true, ...
                "makePlot", false), simulationDir);
            errorCounts(modeIndex, curveIndex, activeIndices) = ...
                errorCounts(modeIndex, curveIndex, activeIndices) + ...
                reshape(local.isiErrorCounts, 1, 1, []);
            bitTotals(modeIndex, curveIndex, activeIndices) = ...
                bitTotals(modeIndex, curveIndex, activeIndices) + ...
                reshape(local.isiBitTotals, 1, 1, []);
        end
    end
end

ber = nan(size(errorCounts));
for modeIndex = 1:numel(modeNames)
    for curveIndex = 1:curveCount
        activeIndices = activeSnr(modeIndex, :);
        ber(modeIndex, curveIndex, activeIndices) = ...
            errorCounts(modeIndex, curveIndex, activeIndices) ./ ...
            bitTotals(modeIndex, curveIndex, activeIndices);
    end
end
plotBer = ber;
zeroMask = plotBer == 0;
plotBer(zeroMask) = 3 ./ bitTotals(zeroMask);
result.config = cfg;
result.modeNames = modeNames;
result.curveLabels = curveLabels;
result.snrList = cfg.snrList;
result.activeSnr = activeSnr;
result.ber = ber;
result.plotBer = plotBer;
result.errorCounts = errorCounts;
result.bitTotals = bitTotals;

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, "fig5_19_gcck_channel_estimation_error.png");
matPath = fullfile(cfg.outputDir, "fig5_19_gcck_channel_estimation_error.mat");
csvPath = fullfile(cfg.outputDir, "fig5_19_gcck_channel_estimation_error.csv");
fig = figure("Color", "w", "Position", [100 40 1040 940], "Visible", "off");
axesPosition = {[0.09 0.63 0.34 0.29], [0.57 0.63 0.34 0.29], ...
    [0.33 0.18 0.34 0.29]};
markers = {"o", "<", "s", "d", "none"};
lineStyles = {"--", "--", "--", "--", "-"};
colors = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.93 0.69 0.13; ...
    0.49 0.18 0.56; 0.18 0.55 0.34];
for modeIndex = 1:numel(modeNames)
    ax = axes(fig, "Position", axesPosition{modeIndex}); hold(ax, "on");
    activeIndices = activeSnr(modeIndex, :);
    for curveIndex = 1:curveCount
        semilogy(ax, cfg.snrList(activeIndices), ...
            squeeze(plotBer(modeIndex, curveIndex, activeIndices)).', ...
            "Color", colors(curveIndex, :), "LineStyle", lineStyles{curveIndex}, ...
            "Marker", markers{curveIndex}, "LineWidth", 1.0, ...
            "MarkerSize", 4.8, "DisplayName", curveLabels(curveIndex));
    end
    grid(ax, "on"); ax.GridAlpha = 0.55; ax.GridLineStyle = "--";
    ax.YScale = "log";
    xlim(ax, [0 cfg.modeSnrMaximum(modeIndex)]);
    xticks(ax, 0:2:cfg.modeSnrMaximum(modeIndex));
    if modeIndex < 3
        ylim(ax, [1e-5 1]);
    else
        ylim(ax, [1e-4 1]);
    end
    xlabel(ax, {"信噪比/dB", panelLabels(modeIndex)});
    ylabel(ax, "误码率");
    legend(ax, "Location", "southwest", "Interpreter", "tex");
end
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei", "FontSize", 10);
annotation(fig, "textbox", [0.22 0.055 0.56 0.04], "String", ...
    "图5-19 信道估计误差对不同 GCCK 调制的性能影响", ...
    "EdgeColor", "none", "HorizontalAlignment", "center", ...
    "FontName", "Microsoft YaHei", "FontSize", 12);
exportgraphics(fig, figurePath, "Resolution", 220); close(fig);

modeColumn = strings(0, 1);
curveColumn = strings(0, 1);
snrColumn = zeros(0, 1);
berColumn = zeros(0, 1);
errorColumn = zeros(0, 1);
bitColumn = zeros(0, 1);
for modeIndex = 1:numel(modeNames)
    activeIndices = activeSnr(modeIndex, :);
    for curveIndex = 1:curveCount
        count = sum(activeIndices);
        modeColumn = [modeColumn; repmat(modeNames(modeIndex), count, 1)];
        curveColumn = [curveColumn; repmat(curveLabels(curveIndex), count, 1)];
        snrColumn = [snrColumn; cfg.snrList(activeIndices).'];
        berColumn = [berColumn; squeeze(ber(modeIndex, curveIndex, activeIndices))];
        errorColumn = [errorColumn; squeeze(errorCounts(modeIndex, curveIndex, activeIndices))];
        bitColumn = [bitColumn; squeeze(bitTotals(modeIndex, curveIndex, activeIndices))];
    end
end
writetable(table(modeColumn, curveColumn, snrColumn, berColumn, errorColumn, ...
    bitColumn, 'VariableNames', {'Modulation', 'EstimationError', 'SNR_dB', ...
    'BER', 'ErrorCount', 'BitTotal'}), csvPath);
result.figurePath = figurePath;
result.matPath = matPath;
result.csvPath = csvPath;
save(matPath, "result", "cfg");
end

function output = merge_options_local(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
