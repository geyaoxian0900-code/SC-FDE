function result = simulate_chapter5_figure522(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE522 Calculate aperiodic autocorrelation of CCK words.
if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
defaults.referenceBlockIndices = {[1], [1, 131], [1, 131, 2, 130]};
cfg = merge_options_local(defaults, options);

codewordLengths = [8, 16, 32];
panelLabels = ["(a) CCK-8", "(b) CCK-16", "(c) CCK-32"];
lineColors = [0.00 0.38 0.68; 0.80 0.30 0.08; 0.18 0.56 0.34];
cckBook = cck8_codebook();
words = cell(1, numel(codewordLengths));
correlations = cell(1, numel(codewordLengths));
lags = cell(1, numel(codewordLengths));

for index = 1:numel(codewordLengths)
    blockIndices = cfg.referenceBlockIndices{index};
    validateattributes(blockIndices, {'numeric'}, {'vector', 'integer', ...
        '>=', 1, '<=', size(cckBook, 1)});
    words{index} = reshape(cckBook(blockIndices, :).', 1, []);
    [lags{index}, correlations{index}] = aperiodic_autocorrelation(words{index});
end

result.config = cfg;
result.codewordLengths = codewordLengths;
result.selectedBlockIndices = cfg.referenceBlockIndices;
result.codewords = words;
result.lags = lags;
result.normalizedAutocorrelationMagnitude = correlations;

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, "fig5_22_cck_autocorrelation.png");
matPath = fullfile(cfg.outputDir, "fig5_22_cck_autocorrelation.mat");
csvPath = fullfile(cfg.outputDir, "fig5_22_cck_autocorrelation.csv");

fig = figure("Color", "w", "Position", [100, 55, 1160, 890], "Visible", "off");
axesPositions = {[0.09, 0.61, 0.37, 0.31], [0.59, 0.61, 0.37, 0.31], ...
    [0.34, 0.17, 0.37, 0.31]};
for index = 1:numel(codewordLengths)
    ax = axes(fig, "Position", axesPositions{index});
    plot(ax, lags{index}, correlations{index}, "Color", lineColors(index, :), ...
        "LineWidth", 1.35);
    box(ax, "on");
    xlim(ax, [-(codewordLengths(index) - 1), codewordLengths(index) - 1]);
    ylim(ax, [0, 1]);
    yticks(ax, 0:0.2:1);
    if codewordLengths(index) == 8
        xticks(ax, -6:2:6);
    elseif codewordLengths(index) == 16
        xticks(ax, -15:5:15);
    else
        xticks(ax, -30:10:30);
    end
    xlabel(ax, {"閺冭泛娆㈤敍鍫㈢垳閻楀浄绱?, panelLabels(index)});
    ylabel(ax, "瑜版帊绔撮崠鏍х畽鎼?);
    ax.FontName = "Microsoft YaHei";
    ax.FontSize = 10.5;
    ax.LineWidth = 1;
end
annotation(fig, "textbox", [0.20, 0.045, 0.60, 0.045], "String", ...
    "閸?5-22  娑撳秴鎮撻梹鍨 CCK 閻礁鐡ч惃鍕殰閻╃鍙х紒鎾寸亯", "EdgeColor", "none", ...
    "HorizontalAlignment", "center", "FontName", "Microsoft YaHei", ...
    "FontSize", 13);
exportgraphics(fig, figurePath, "Resolution", 220);
close(fig);

lengthColumn = zeros(0, 1);
lagColumn = zeros(0, 1);
correlationColumn = zeros(0, 1);
for index = 1:numel(codewordLengths)
    sampleCount = numel(lags{index});
    lengthColumn = [lengthColumn; repmat(codewordLengths(index), sampleCount, 1)];
    lagColumn = [lagColumn; lags{index}(:)];
    correlationColumn = [correlationColumn; correlations{index}(:)];
end
writetable(table(lengthColumn, lagColumn, correlationColumn, 'VariableNames', ...
    {'CodewordLength', 'LagChip', 'NormalizedAutocorrelationMagnitude'}), csvPath);

result.figurePath = figurePath;
result.matPath = matPath;
result.csvPath = csvPath;
save(matPath, "result", "cfg");
end

function book = cck8_codebook()
book = complex(zeros(256, 8));
for index = 0:255
    bits = bitget(index, 1:8);
    qpsk = @(pair) pi * pair(1) + 0.5 * pi * pair(2);
    phase = [qpsk(bits(1:2)), qpsk(bits(3:4)), ...
        qpsk(bits(5:6)), qpsk(bits(7:8))];
    word = exp(1j * [phase(1) + phase(2) + phase(3) + phase(4), ...
        phase(1) + phase(3) + phase(4), phase(1) + phase(2) + phase(4), ...
        phase(1) + phase(4), phase(1) + phase(2) + phase(3), ...
        phase(1) + phase(3), phase(1) + phase(2), phase(1)]);
    word([4, 7]) = -word([4, 7]);
    book(index + 1, :) = word;
end
end

function [lags, magnitude] = aperiodic_autocorrelation(word)
wordLength = numel(word);
lags = -(wordLength - 1):(wordLength - 1);
magnitude = zeros(size(lags));
wordEnergy = sum(abs(word).^2);
for index = 1:numel(lags)
    lag = lags(index);
    if lag >= 0
        correlation = sum(word(1:wordLength - lag) .* conj(word(1 + lag:end)));
    else
        correlation = sum(word(1 - lag:end) .* conj(word(1:wordLength + lag)));
    end
    magnitude(index) = abs(correlation) / wordEnergy;
end
end

function output = merge_options_local(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
