function result = simulate_chapter5_figure523(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE523 Evaluate CCK word lengths over a multipath channel.
if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrList = 0:2:10;
defaults.minimumWords = 4096;
defaults.maximumWords = 16000;
defaults.minimumBitErrors = 80;
defaults.wordsPerBatch = 512;
defaults.randomSeed = 20260807;
defaults.channel = chapter5_multipath_channel();
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options_local(defaults, options);
cfg.channel = cfg.channel(:).';
cfg.channel = cfg.channel / norm(cfg.channel);

wordLengths = [8, 16, 32];
labels = ["CCK-8", "CCK-16", "CCK-32"];
colors = [0.00, 0.33, 0.68; 0.85, 0.33, 0.10; 0.12, 0.52, 0.30];
markers = {"s", "d", "p"};
bookCount = numel(wordLengths);
snrCount = numel(cfg.snrList);
ber = zeros(bookCount, snrCount);
plotBer = zeros(bookCount, snrCount);
errorCounts = zeros(bookCount, snrCount);
bitTotals = zeros(bookCount, snrCount);
wordTotals = zeros(bookCount, snrCount);

for lengthIndex = 1:bookCount
    [book, bits] = extended_cck_codebook(wordLengths(lengthIndex));
    templates = channel_templates(book, cfg.channel);
    for snrIndex = 1:snrCount
        seed = cfg.randomSeed + 1000 * lengthIndex + snrIndex;
        [errorCounts(lengthIndex, snrIndex), bitTotals(lengthIndex, snrIndex), ...
            wordTotals(lengthIndex, snrIndex)] = simulate_point(book, bits, ...
            templates, cfg.channel, cfg.snrList(snrIndex), cfg, seed);
    end
end

ber = errorCounts ./ bitTotals;
plotBer = max(ber, 0.5 ./ bitTotals);
result.config = cfg;
result.wordLengths = wordLengths;
result.labels = labels;
result.snrList = cfg.snrList;
result.ber = ber;
result.plotBer = plotBer;
result.errorCounts = errorCounts;
result.bitTotals = bitTotals;
result.wordTotals = wordTotals;
result.zeroErrorDisplayConvention = "0.5 / BitTotal";

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, "fig5_23_cck_multipath_ber.png");
matPath = fullfile(cfg.outputDir, "fig5_23_cck_multipath_ber.mat");
csvPath = fullfile(cfg.outputDir, "fig5_23_cck_multipath_ber.csv");
fig = figure("Color", "w", "Position", [160, 80, 940, 790], "Visible", "off");
ax = axes(fig, "Position", [0.16, 0.22, 0.73, 0.70]);
hold(ax, "on");
for lengthIndex = 1:bookCount
    markerFaceColor = 'w';
    if lengthIndex == 3
        markerFaceColor = colors(lengthIndex, :);
    end
    plot(ax, cfg.snrList, log10(plotBer(lengthIndex, :)), "Color", colors(lengthIndex, :), ...
        "LineWidth", 1.35, "Marker", markers{lengthIndex}, "MarkerSize", 8, ...
        "MarkerFaceColor", markerFaceColor, ...
        "DisplayName", labels(lengthIndex));
end
box(ax, "on");
grid(ax, "on");
ax.YMinorGrid = "on";
ax.GridLineStyle = "--";
ax.MinorGridLineStyle = "--";
ax.GridAlpha = 0.34;
ax.MinorGridAlpha = 0.24;
ax.FontName = "Microsoft YaHei";
ax.FontSize = 11;
ax.LineWidth = 1;
ax.YDir = "normal";
xlim(ax, [0, 12]);
ylim(ax, [-5, 0]);
yticks(ax, -5:0);
yticklabels(ax, {"10^{-5}", "10^{-4}", "10^{-3}", "10^{-2}", ...
    "10^{-1}", "10^{0}"});
xticks(ax, 0:2:12);
xlabel(ax, "E_b/N_0 (dB)", "Interpreter", "tex");
ylabel(ax, "BER");
legend(ax, "Location", "northeast", "FontSize", 10.5);
annotation(fig, "textbox", [0.17, 0.055, 0.68, 0.055], "String", ...
    "Fig 5-23: CCK word BER over multipath channel", ...
    "EdgeColor", "none", "HorizontalAlignment", "center", ...
    "FontName", "Microsoft YaHei", "FontSize", 14);
exportgraphics(fig, figurePath, "Resolution", 220);
close(fig);

lengthColumn = zeros(0, 1);
snrColumn = zeros(0, 1);
berColumn = zeros(0, 1);
plotBerColumn = zeros(0, 1);
errorColumn = zeros(0, 1);
bitColumn = zeros(0, 1);
wordColumn = zeros(0, 1);
for lengthIndex = 1:bookCount
    lengthColumn = [lengthColumn; repmat(wordLengths(lengthIndex), snrCount, 1)];
    snrColumn = [snrColumn; cfg.snrList(:)];
    berColumn = [berColumn; ber(lengthIndex, :).'];
    plotBerColumn = [plotBerColumn; plotBer(lengthIndex, :).'];
    errorColumn = [errorColumn; errorCounts(lengthIndex, :).'];
    bitColumn = [bitColumn; bitTotals(lengthIndex, :).'];
    wordColumn = [wordColumn; wordTotals(lengthIndex, :).'];
end
writetable(table(lengthColumn, snrColumn, berColumn, plotBerColumn, errorColumn, ...
    bitColumn, wordColumn, 'VariableNames', {'CodewordLength', 'EbN0_dB', ...
    'BER', 'DisplayBER', 'ErrorCount', 'BitTotal', 'WordTotal'}), csvPath);
result.figurePath = figurePath;
result.matPath = matPath;
result.csvPath = csvPath;
save(matPath, "result", "cfg");
end

function [errors, bitTotal, wordTotal] = simulate_point(book, bits, templates, ...
        channel, snrDb, cfg, seed)
rng(seed, "twister");
errors = 0;
bitTotal = 0;
wordTotal = 0;
energyPerBit = mean(sum(abs(book).^2, 2)) / size(bits, 2);
noiseVariance = energyPerBit * 10^(-snrDb / 10);
while wordTotal < cfg.maximumWords && ...
        (wordTotal < cfg.minimumWords || errors < cfg.minimumBitErrors)
    count = min(cfg.wordsPerBatch, cfg.maximumWords - wordTotal);
    transmitted = randi(size(book, 1), count, 1);
    chips = reshape(book(transmitted, :).', [], 1);
    received = filter(channel, 1, chips) + sqrt(noiseVariance / 2) * ...
        (randn(size(chips)) + 1j * randn(size(chips)));
    detected = dfe_ml_detect(received, book, templates, channel);
    errors = errors + sum(sum(bits(detected, :) ~= bits(transmitted, :)));
    bitTotal = bitTotal + count * size(bits, 2);
    wordTotal = wordTotal + count;
end
end

function templates = channel_templates(book, channel)
wordLength = size(book, 2);
memory = numel(channel) - 1;
templates = complex(zeros(size(book)));
for index = 1:size(book, 1)
    response = filter(channel, 1, [zeros(memory, 1); book(index, :).']);
    templates(index, :) = response(memory + (1:wordLength)).';
end
end

function detected = dfe_ml_detect(received, book, templates, channel)
wordLength = size(book, 2);
memory = numel(channel) - 1;
blockCount = floor(numel(received) / wordLength);
templateEnergy = sum(abs(templates).^2, 2);
state = zeros(memory, 1);
detected = zeros(blockCount, 1);
for block = 1:blockCount
    sampleRange = (block - 1) * wordLength + (1:wordLength);
    interference = filter(channel, 1, [state; zeros(wordLength, 1)]);
    observation = received(sampleRange) - interference(memory + (1:wordLength));
    metric = templateEnergy - 2 * real(templates * conj(observation));
    [~, detected(block)] = min(metric);
    state = [state; book(detected(block), :).'];
    state = state(end - memory + 1:end);
end
end

function [book, bits] = extended_cck_codebook(wordLength)
baseBook = cck8_codebook();
if ~ismember(wordLength, [8, 16, 32])
    error("SCFDE:UnsupportedCCKLength", "Supported CCK lengths are 8, 16, and 32.");
end
book = complex(zeros(256, wordLength));
bits = zeros(256, 8);
for index = 0:255
    rowBits = bitget(index, 1:8);
    bits(index + 1, :) = rowBits;
    blockCount = wordLength / 8;
    if blockCount == 1
        signs = 1;
    elseif blockCount == 2
        signs = [1, 1 - 2 * rowBits(3)];
    else
        patterns = [1, 1, 1, 1; 1, -1, 1, -1; ...
            1, 1, -1, -1; 1, -1, -1, 1];
        signs = patterns(1 + rowBits(3) + 2 * rowBits(4), :);
    end
    book(index + 1, :) = repmat(baseBook(index + 1, :), 1, blockCount) .* ...
        repelem(signs, 8);
end
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

function channel = long_uwa_channel()
delays = [0, 1, 2, 3, 4, 5, 7, 9, 11, 13, 15];
power = exp(-delays / 5.5);
phase = [0, 0.5, -1.0, 0.8, -2.1, 0.25, -1.5, 1.4, -0.8, 0.9, -2.6];
channel = complex(zeros(1, delays(end) + 1));
channel(delays + 1) = sqrt(power) .* exp(1j * phase);
channel = channel / norm(channel);
end

function channel = chapter5_multipath_channel()
channel = long_uwa_channel();
channel(2:end) = 0.45 * channel(2:end);
channel = channel / norm(channel);
end

function output = merge_options_local(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
