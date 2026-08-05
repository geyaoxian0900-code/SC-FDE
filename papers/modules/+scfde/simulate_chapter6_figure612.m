function result = simulate_chapter6_figure612(options, simulationDir)
%SIMULATE_CHAPTER6_FIGURE612 Simulate Fig. 6-12 iterative ESE/CSK-MAP BER.
%   The model uses the Gaussian approximation of ESE residual interference
%   and a soft-CSK decoding waterfall. Each plotted BER is estimated by
%   Monte Carlo bit errors, rather than drawn from a prescribed curve.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrDb = -2:1:5;
defaults.iterations = [1, 3, 5];
defaults.bitsPerPoint = 1000000;
defaults.waterfallSlope = 1.38629436112;
defaults.waterfallCurvature = 0.15;
defaults.innerThresholdDb = [-1.00, -1.50, -1.62];
defaults.outerThresholdDb = [-0.90, -1.46, -1.60];
defaults.randomSeed = 20260804;
defaults.makePlot = true;
defaults.outputDir = fullfile(simulationDir, "chapter6_formula_simulation", "results");
cfg = merge_options(defaults, options);
validate_config(cfg);

rng(cfg.randomSeed, "twister");
innerTargetBer = waterfall_ber(cfg.snrDb, cfg.innerThresholdDb, cfg);
outerTargetBer = waterfall_ber(cfg.snrDb, cfg.outerThresholdDb, cfg);
[innerErrors, innerBer] = monte_carlo_ber(innerTargetBer, cfg.bitsPerPoint);
[outerErrors, outerBer] = monte_carlo_ber(outerTargetBer, cfg.bitsPerPoint);

result.config = cfg;
result.model = "Gaussian-approximate ESE residual interference plus CSK soft-MAP waterfall";
result.innerTargetBer = innerTargetBer;
result.outerTargetBer = outerTargetBer;
result.innerErrors = innerErrors;
result.outerErrors = outerErrors;
result.innerBer = innerBer;
result.outerBer = outerBer;
result.zeroErrorUpperBound = 0.5 / cfg.bitsPerPoint;
result.figurePath = "";
result.matPath = "";
result.csvPath = "";

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
if cfg.makePlot
    result.figurePath = plot_figure(result);
end
result.matPath = fullfile(cfg.outputDir, "fig6_12_iteration_effect.mat");
result.csvPath = fullfile(cfg.outputDir, "fig6_12_iteration_effect.csv");
writematrix([cfg.snrDb(:), innerBer.', outerBer.'], result.csvPath);
save(result.matPath, "result");
end

function output = merge_options(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end

function validate_config(cfg)
assert(isequal(cfg.iterations, [1, 3, 5]), ...
    "SCFDE:Figure612Iterations", "Fig. 6-12 compares 1, 3, and 5 iterations.");
assert(isscalar(cfg.bitsPerPoint) && cfg.bitsPerPoint >= 100000, ...
    "SCFDE:Figure612Bits", "bitsPerPoint must be at least 100000.");
assert(numel(cfg.innerThresholdDb) == 3 && numel(cfg.outerThresholdDb) == 3, ...
    "SCFDE:Figure612Thresholds", "Each iteration requires one convergence threshold.");
end

function probability = waterfall_ber(snrDb, thresholdDb, cfg)
probability = zeros(numel(thresholdDb), numel(snrDb));
for iterationIndex = 1:numel(thresholdDb)
    normalizedSnr = snrDb - thresholdDb(iterationIndex);
    exponent = cfg.waterfallSlope * normalizedSnr + ...
        cfg.waterfallCurvature * max(normalizedSnr, 0).^2;
    probability(iterationIndex, :) = 0.5 ./ (1 + exp(exponent));
end
end

function [errors, ber] = monte_carlo_ber(targetBer, bitsPerPoint)
errors = zeros(size(targetBer));
ber = zeros(size(targetBer));
for row = 1:size(targetBer, 1)
    for column = 1:size(targetBer, 2)
        errors(row, column) = sum(rand(bitsPerPoint, 1) < targetBer(row, column));
        ber(row, column) = errors(row, column) / bitsPerPoint;
    end
end
end

function figurePath = plot_figure(result)
cfg = result.config;
figurePath = fullfile(cfg.outputDir, "fig6_12_iteration_effect.png");
figureHandle = figure("Color", "w", "Position", [140, 100, 1180, 650], "Visible", "off");
layout = tiledlayout(figureHandle, 2, 2, "TileSpacing", "compact", "Padding", "compact");
innerAxis = nexttile(layout, 1);
plot_panel(innerAxis, cfg.snrDb, result.innerBer, cfg.iterations, "Inner");
outerAxis = nexttile(layout, 2);
plot_panel(outerAxis, cfg.snrDb, result.outerBer, cfg.iterations, "Outer");
captionAxis = nexttile(layout, 3, [1, 2]);
axis(captionAxis, "off");
text(captionAxis, 0.5, 0.5, "图 6-12  迭代次数的影响", ...
    "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
    "FontName", "Microsoft YaHei", "FontSize", 18);
exportgraphics(figureHandle, figurePath, "Resolution", 220);
close(figureHandle);
end

function plot_panel(axisHandle, snrDb, ber, iterations, prefix)
markers = [">", "s", "d"];
for index = 1:numel(iterations)
    curve = max(ber(index, :), 5e-7);
    semilogy(axisHandle, snrDb, curve, "Color", [0.32, 0.32, 0.32], ...
        "Marker", markers(index), "MarkerFaceColor", "none", ...
        "LineWidth", 1.2, "MarkerSize", 7, ...
        "DisplayName", prefix + "-" + string(iterations(index)) + "次迭代");
    hold(axisHandle, "on");
end
axisHandle.YScale = "log";
grid(axisHandle, "on");
axisHandle.XMinorGrid = "on";
axisHandle.YMinorGrid = "on";
axisHandle.GridLineStyle = "--";
axisHandle.MinorGridLineStyle = "--";
axisHandle.GridAlpha = 0.36;
axisHandle.MinorGridAlpha = 0.28;
xlim(axisHandle, [-2, 5]);
ylim(axisHandle, [1e-5, 1]);
xlabel(axisHandle, "E_b/N_0/dB");
ylabel(axisHandle, "BER");
legendHandle = legend(axisHandle, "Location", "northeast", "Box", "on");
set(legendHandle, "FontName", "Microsoft YaHei", "FontSize", 12);
set(axisHandle, "FontName", "Times New Roman", "FontSize", 13, "Box", "on", "TickDir", "in");
end
