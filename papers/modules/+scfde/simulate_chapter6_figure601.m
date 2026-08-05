function result = simulate_chapter6_figure601(options, simulationDir)
%SIMULATE_CHAPTER6_FIGURE601 Reproduce Fig. 6-1 cyclic-shift spreading.
%   A deterministic 256-chip bipolar PN waveform is circularly shifted by
%   49 chips. The receiver evaluates all cyclic shifts of the local waveform.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.codeLength = 256;
defaults.shiftChips = 49;
defaults.randomSeed = 20260804;
defaults.noiseStd = 0;
defaults.makePlot = true;
defaults.outputDir = fullfile(simulationDir, "chapter6_formula_simulation", "results");
cfg = merge_options(defaults, options);
validate_config(cfg);

rng(cfg.randomSeed, "twister");
baseWaveform = 2 * randi([0, 1], 1, cfg.codeLength) - 1;
shiftedWaveform = circshift(baseWaveform, -cfg.shiftChips);
receivedWaveform = shiftedWaveform + cfg.noiseStd * randn(size(shiftedWaveform));

correlation = zeros(1, cfg.codeLength);
for trialShift = 0:cfg.codeLength - 1
    localWaveform = circshift(baseWaveform, -trialShift);
    correlation(trialShift + 1) = real(sum(receivedWaveform .* conj(localWaveform)));
end
correlation = correlation / max(abs(correlation));
[peakValue, peakIndex] = max(correlation);

result.config = cfg;
result.baseWaveform = baseWaveform;
result.shiftedWaveform = shiftedWaveform;
result.receivedWaveform = receivedWaveform;
result.trialShiftChips = 0:cfg.codeLength - 1;
result.normalizedCorrelation = correlation;
result.estimatedShiftChips = peakIndex - 1;
result.peakValue = peakValue;
result.figurePath = "";
result.matPath = "";
result.csvPath = "";

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
result.matPath = fullfile(cfg.outputDir, "fig6_1_cyclic_shift_spreading.mat");
result.csvPath = fullfile(cfg.outputDir, "fig6_1_cyclic_shift_correlation.csv");
save(result.matPath, "result");
writematrix([result.trialShiftChips(:), result.normalizedCorrelation(:)], result.csvPath);

if cfg.makePlot
    result.figurePath = plot_figure(result);
end
end

function output = merge_options(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end

function validate_config(cfg)
assert(isscalar(cfg.codeLength) && cfg.codeLength >= 8 && mod(cfg.codeLength, 1) == 0, ...
    "SCFDE:InvalidCodeLength", "codeLength must be an integer no smaller than 8.");
assert(isscalar(cfg.shiftChips) && cfg.shiftChips >= 0 && cfg.shiftChips < cfg.codeLength && ...
    mod(cfg.shiftChips, 1) == 0, "SCFDE:InvalidShift", ...
    "shiftChips must be an integer in [0, codeLength-1].");
assert(isscalar(cfg.noiseStd) && cfg.noiseStd >= 0, ...
    "SCFDE:InvalidNoise", "noiseStd must be nonnegative.");
end

function figurePath = plot_figure(result)
cfg = result.config;
figurePath = fullfile(cfg.outputDir, "fig6_1_cyclic_shift_spreading.png");
fig = figure("Color", "w", "Position", [150, 50, 960, 940], "Visible", "off");
layout = tiledlayout(fig, 3, 1, "TileSpacing", "compact", "Padding", "compact");

topAxes = nexttile(layout, 1);
draw_codeword_strip(topAxes, cfg.codeLength, 0.70, "(a) 基本波形");
draw_codeword_strip(topAxes, cfg.codeLength, 0.10, "(b) 循环移位", cfg.shiftChips);
axis(topAxes, "off");

correlationAxes = nexttile(layout, 2);
plot(correlationAxes, result.trialShiftChips + 1, result.normalizedCorrelation, ...
    "Color", [0.20, 0.20, 0.20], "LineWidth", 1.15);
grid(correlationAxes, "on");
xlim(correlationAxes, [1, cfg.codeLength]);
ylim(correlationAxes, [-0.2, 1.2]);
xlabel(correlationAxes, "码元位数");
ylabel(correlationAxes, "归一化相关输出");
title(correlationAxes, "(c) 相关输出");
set(correlationAxes, "FontName", "Microsoft YaHei", "FontSize", 12, "GridAlpha", 0.16);

captionAxes = nexttile(layout, 3);
axis(captionAxes, "off");
text(captionAxes, 0.5, 0.5, "图6-1  循环移位扩频示意图", ...
    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
    "FontName", "Microsoft YaHei", "FontSize", 18);
exportgraphics(fig, figurePath, "Resolution", 220);
close(fig);
end

function draw_codeword_strip(axisHandle, codeLength, yCenter, caption, shiftChips)
if nargin < 5
    shiftChips = 0;
end
segments = ones(1, 8);
labels = compose("%d", [1, 2, NaN, 50, 51, NaN, 255, 256]);
if shiftChips ~= 0
    labels = compose("%d", [50, 51, NaN, 256, 1, 2, NaN, 49]);
    labels([3, 7]) = "...";
else
    labels([3, 6]) = "...";
end
edges = [0, cumsum(segments)];
for segmentIndex = 1:numel(segments)
    xLeft = edges(segmentIndex) / sum(segments);
    width = segments(segmentIndex) / sum(segments);
    rectangle(axisHandle, "Position", [xLeft, yCenter, width, 0.30], ...
        "FaceColor", [0.985, 0.985, 0.985], "EdgeColor", [0.18, 0.18, 0.18], "LineWidth", 1.05);
    text(axisHandle, xLeft + width / 2, yCenter + 0.15, labels(segmentIndex), ...
        "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
        "FontName", "Times New Roman", "FontSize", 13);
end
text(axisHandle, 0.5, yCenter - 0.10, caption, "HorizontalAlignment", "center", ...
    "VerticalAlignment", "top", "FontName", "Microsoft YaHei", "FontSize", 14);
xlim(axisHandle, [0, 1]);
ylim(axisHandle, [0, 1.15]);
end
