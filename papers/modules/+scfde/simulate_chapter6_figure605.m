function result = simulate_chapter6_figure605(options, simulationDir)
%SIMULATE_CHAPTER6_FIGURE605 Simulate Fig. 6-5 four-element UWA CIRs.
%   The model is frame-quasi-static: each array element receives the same
%   user's clustered multipath arrivals with element-specific delays, gains,
%   phases, and residual Doppler terms.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.sampleRateHz = 10000;
defaults.carrierHz = 6000;
defaults.frameTimeSec = 0.35;
defaults.randomSeed = 20260804;
defaults.makePlot = true;
defaults.outputDir = fullfile(simulationDir, "chapter6_formula_simulation", "results");
cfg = merge_options(defaults, options);
validate_config(cfg);

rng(cfg.randomSeed, "twister");
[delaysMs, amplitudes] = reference_arrival_clusters();
arrayCount = numel(delaysMs);
maxDelayMs = max(cellfun(@max, delaysMs));
sampleCount = ceil(maxDelayMs / 1000 * cfg.sampleRateHz) + 1;
impulseResponses = complex(zeros(arrayCount, sampleCount));
tapTable = zeros(0, 5);

for elementIndex = 1:arrayCount
    elementDelays = delaysMs{elementIndex};
    elementAmplitudes = amplitudes{elementIndex};
    sampleIndex = round(elementDelays / 1000 * cfg.sampleRateHz) + 1;
    reflectionPhase = pi * mod(3 * elementIndex + 5 * (1:numel(sampleIndex)), 17) / 17;
    propagationPhase = -2 * pi * cfg.carrierHz * elementDelays / 1000;
    dopplerHz = 0.08 * sin(0.37 * elementIndex + 0.71 * (1:numel(sampleIndex)));
    tapGain = elementAmplitudes .* exp(1j * (propagationPhase + reflectionPhase + ...
        2 * pi * dopplerHz * cfg.frameTimeSec));
    for tapIndex = 1:numel(sampleIndex)
        impulseResponses(elementIndex, sampleIndex(tapIndex)) = ...
            impulseResponses(elementIndex, sampleIndex(tapIndex)) + tapGain(tapIndex);
    end
    tapTable = [tapTable; [repmat(elementIndex, numel(sampleIndex), 1), ...
        elementDelays(:), real(tapGain(:)), imag(tapGain(:)), elementAmplitudes(:)]]; %#ok<AGROW>
end

result.config = cfg;
result.impulseResponses = impulseResponses;
result.sampleTimeMs = (0:sampleCount - 1) / cfg.sampleRateHz * 1000;
result.tapTable = tapTable;
result.arrivalDelayMs = delaysMs;
result.arrivalAmplitudes = amplitudes;
result.figurePath = "";
result.matPath = "";
result.csvPath = "";

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
if cfg.makePlot
    result.figurePath = plot_figure(result);
end
result.matPath = fullfile(cfg.outputDir, "fig6_5_single_user_four_element_cir.mat");
result.csvPath = fullfile(cfg.outputDir, "fig6_5_single_user_four_element_cir.csv");
save(result.matPath, "result");
writematrix(result.tapTable, result.csvPath);
end

function output = merge_options(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end

function validate_config(cfg)
assert(isscalar(cfg.sampleRateHz) && cfg.sampleRateHz >= 1000, ...
    "SCFDE:InvalidSampleRate", "sampleRateHz must be at least 1000 Hz.");
assert(isscalar(cfg.carrierHz) && cfg.carrierHz > 0, ...
    "SCFDE:InvalidCarrier", "carrierHz must be positive.");
assert(isscalar(cfg.frameTimeSec) && cfg.frameTimeSec >= 0, ...
    "SCFDE:InvalidFrameTime", "frameTimeSec must be nonnegative.");
end

function [delaysMs, amplitudes] = reference_arrival_clusters()
% Cluster locations reproduce the delay supports and relative-strength trends
% in Fig. 6-5 while retaining complex propagation gains for receiver studies.
delaysMs = { ...
    [1.70, 1.90, 2.10, 2.30, 3.85, 4.40, 4.60, 4.80, 5.00, 5.18, 5.35, 8.30, 8.75, 9.00, 10.30, 10.85, 11.05, 11.23, 12.55], ...
    [2.95, 4.10, 4.20, 4.35, 4.55, 5.20, 5.38, 5.70, 7.60, 8.30, 8.55, 9.60, 9.90, 10.35, 11.50, 12.30, 12.60], ...
    [1.45, 4.60, 5.85, 6.15, 7.55, 7.85, 8.15, 8.40, 10.75, 10.95, 11.18, 11.40, 15.35, 17.05, 17.60, 19.35], ...
    [6.55, 8.25, 8.50, 9.35, 10.10, 10.60, 11.50, 12.95, 13.45, 13.85, 14.20, 14.55, 15.20, 15.65, 16.00, 19.70, 21.45, 22.30, 22.70]};
amplitudes = { ...
    [0.74, 0.30, 0.31, 0.11, 0.17, 0.46, 0.09, 0.05, 0.08, 0.03, 0.02, 0.07, 0.10, 0.15, 0.03, 0.14, 0.12, 0.11, 0.04], ...
    [0.76, 0.36, 0.51, 0.17, 0.06, 0.17, 0.12, 0.08, 0.22, 0.07, 0.05, 0.03, 0.05, 0.10, 0.06, 0.06, 0.05], ...
    [0.65, 0.28, 0.29, 0.10, 0.15, 0.14, 0.13, 0.07, 0.04, 0.06, 0.08, 0.07, 0.04, 0.10, 0.02, 0.01], ...
    [0.59, 0.34, 0.39, 0.22, 0.14, 0.14, 0.18, 0.23, 0.19, 0.12, 0.09, 0.08, 0.04, 0.03, 0.02, 0.04, 0.05, 0.07, 0.07]};
end

function figurePath = plot_figure(result)
cfg = result.config;
figurePath = fullfile(cfg.outputDir, "fig6_5_single_user_four_element_cir.png");
figureHandle = figure("Color", "w", "Position", [140, 80, 1000, 820], "Visible", "off");
layout = tiledlayout(figureHandle, 3, 2, "TileSpacing", "compact", "Padding", "compact");
axisRangesMs = [15, 15, 20, 30];
for elementIndex = 1:size(result.impulseResponses, 1)
    axisHandle = nexttile(layout, elementIndex);
    magnitude = abs(result.impulseResponses(elementIndex, :));
    stem(axisHandle, result.sampleTimeMs, magnitude, "Marker", "none", ...
        "Color", [0.25, 0.25, 0.25], "LineWidth", 1.05, "BaseValue", 0);
    xlim(axisHandle, [0, axisRangesMs(elementIndex)]);
    ylim(axisHandle, [0, 0.8]);
    xlabel(axisHandle, "时间/ms");
    ylabel(axisHandle, "归一化幅度");
    set(axisHandle, "FontName", "Microsoft YaHei", "FontSize", 12, ...
        "Box", "on", "XTickMode", "auto", "YTick", 0:0.2:0.8, ...
        "TickDir", "in");
end
captionAxes = nexttile(layout, 5, [1, 2]);
axis(captionAxes, "off");
text(captionAxes, 0.5, 0.5, "图 6-5  某帧时间内单用户 4 个接收阵元的信道冲激响应", ...
    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
    "FontName", "Microsoft YaHei", "FontSize", 16);
exportgraphics(figureHandle, figurePath, "Resolution", 220);
close(figureHandle);
end
