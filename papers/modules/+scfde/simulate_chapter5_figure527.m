function result = simulate_chapter5_figure527(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE527 Compare CCK receivers over a UWA channel.
%   The front-end CCK receivers and RSSE use a four-state main-path
%   equivalent channel. TE-CCK uses the full LDPC-coded UWA link.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrList = -5:10;
defaults.frontEndWords = 24;
defaults.frontEndFrameCount = 12;
defaults.teFrameWords = 96;
defaults.teFrameCount = 24;
defaults.turboIterations = 4;
defaults.teTurboDamping = 0.72;
defaults.teCckLlrScale = 1;
defaults.teLdpcDecoderIterations = 18;
defaults.minimumErrorsForPlot = 3;
defaults.rsseStateCount = 4;
defaults.randomSeed = 20260804;
defaults.channelDelays = [0, 1, 3, 5];
defaults.channelPowerDb = [0, -1.7, -3.8, -6.2];
defaults.channelPhase = [0, 0.48, -1.15, 0.76];
defaults.pathDopplerPerChip = [0, 0.000007, -0.000011, 0.000016];
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options_local(defaults, options);
validate_config(cfg);

channel = equivalent_uwa_channel(cfg);
frontEnd = simulate_front_end_receivers(cfg, channel, simulationDir);
te = simulate_te_cck(cfg, simulationDir);
rsse = simulate_dynamic_rsse(cfg, channel);

methodLabels = ["Rake", "Rake-DFE", "BiDFE（1次迭代）", ...
    "BiDFE（2次迭代）", "TR-Diversity（1次迭代）", ...
    "TR-Diversity（2次迭代）", "RSSE", "TE-CCK-无迭代", ...
    "TE-CCK-1次迭代", "TE-CCK-2次迭代", ...
    "TE-CCK-3次迭代", "TE-CCK-4次迭代"];
methodLabels = ["Rake", "Rake-DFE", "BiDFE（1次迭代）", ...
    "BiDFE（2次迭代）", "TR-Diversity（1次迭代）", ...
    "TR-Diversity（2次迭代）", "RSSE", "TE-CCK-无迭代", ...
    "TE-CCK-1次迭代", "TE-CCK-2次迭代", "TE-CCK-3次迭代", ...
    "TE-CCK-4次迭代"];
methodCount = numel(methodLabels);
snrCount = numel(cfg.snrList);
ber = zeros(methodCount, snrCount);
errorCounts = zeros(methodCount, snrCount);
bitTotals = zeros(methodCount, snrCount);

frontEndIndices = [1, 2, 4, 5, 6, 7];
ber(1:6, :) = frontEnd.isiBer(frontEndIndices, :);
errorCounts(1:6, :) = frontEnd.isiErrorCounts(frontEndIndices, :);
bitTotals(1:6, :) = repmat(frontEnd.isiBitTotals, 6, 1);
ber(7, :) = rsse.ber;
errorCounts(7, :) = rsse.errorCounts;
bitTotals(7, :) = rsse.bitTotals;
ber(8:12, :) = te.ber(2:6, :);
errorCounts(8:12, :) = te.errorCounts(2:6, :);
bitTotals(8:12, :) = te.bitTotals(2:6, :);

displayBer = ber;
lowConfidencePositive = errorCounts > 0 & ...
    errorCounts < cfg.minimumErrorsForPlot;
displayBer(lowConfidencePositive) = nan;
displayBer(errorCounts == 0) = 0.5 ./ bitTotals(errorCounts == 0);

result.config = cfg;
result.channel = channel;
result.methodLabels = methodLabels;
result.snrList = cfg.snrList;
result.ber = ber;
result.displayBer = displayBer;
result.errorCounts = errorCounts;
result.bitTotals = bitTotals;
result.zeroErrorDisplayConvention = "0.5 / BitTotal";
result.frontEnd = frontEnd;
result.te = te;
result.rsse = rsse;

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
result.figurePath = fullfile(cfg.outputDir, "fig5_27_uwa_cck_receiver_ber.png");
result.matPath = fullfile(cfg.outputDir, "fig5_27_uwa_cck_receiver_ber.mat");
result.csvPath = fullfile(cfg.outputDir, "fig5_27_uwa_cck_receiver_ber.csv");
write_figure(result);
write_table(result);
save(result.matPath, "result", "cfg");
end

function validate_config(cfg)
validateattributes(cfg.frontEndWords, {'numeric'}, {'scalar', 'integer', '>=', 4});
validateattributes(cfg.frontEndFrameCount, {'numeric'}, {'scalar', 'integer', '>=', 1});
validateattributes(cfg.teFrameWords, {'numeric'}, {'scalar', 'integer', '>=', 4});
validateattributes(cfg.teFrameCount, {'numeric'}, {'scalar', 'integer', '>=', 1});
assert(numel(cfg.channelDelays) == numel(cfg.channelPowerDb) && ...
    numel(cfg.channelDelays) == numel(cfg.channelPhase), ...
    "SCFDE:InvalidFigure527Channel", "Channel delay, power, and phase vectors must match.");
assert(numel(cfg.channelDelays) == numel(cfg.pathDopplerPerChip), ...
    "SCFDE:InvalidFigure527Doppler", "Each path requires one Doppler rate.");
assert(cfg.channelDelays(1) == 0 && all(diff(cfg.channelDelays) > 0) && ...
    cfg.channelDelays(end) < 8, "SCFDE:InvalidRsseChannelMemory", ...
    "The RSSE equivalent channel memory must be shorter than one CCK word.");
end

function channel = equivalent_uwa_channel(cfg)
channel = complex(zeros(1, cfg.channelDelays(end) + 1));
channel(cfg.channelDelays + 1) = 10 .^ (cfg.channelPowerDb / 20) .* ...
    exp(1j * cfg.channelPhase);
channel = channel / norm(channel);
end

function output = simulate_front_end_receivers(cfg, channel, simulationDir)
options = struct();
options.snrList = cfg.snrList;
options.snrDb = 5;
options.symbols = cfg.frontEndWords;
options.frameCount = cfg.frontEndFrameCount;
options.randomSeed = cfg.randomSeed;
options.turboIterations = cfg.turboIterations;
options.turboDamping = cfg.teTurboDamping;
options.teCckLlrScale = cfg.teCckLlrScale;
options.ldpcDecoderIterations = cfg.teLdpcDecoderIterations;
options.mapStateList = 32;
options.reducedStateList = 16;
options.rsseTrellisStates = 4;
options.turboOuterCode = "repetition-1/2";
options.turboDamping = 0.72;
options.modulationMethods = "FR-CCK";
options.isiModulation = "FR-CCK";
options.isiMethods = "all";
options.turboMethods = "all";
options.runAwgn = false;
options.runIsi = true;
options.runTurbo = true;
options.normalizeIsiChannel = false;
options.receiverSnrDefinition = "EbN0";
options.isiReceiverProfile = "gcckFigure517";
options.receiverBranchCount = 1;
options.isiChannel = channel;
options.receiverChannel = channel;
options.timeVaryingCorrelation = 1;
options.makePlot = false;
options.skipDiagnostics = true;
options.outputDir = fullfile(cfg.outputDir, "fig5_27_internal_frontend");
output = scfde.run_chapter5_cck_suite_impl(options, simulationDir);
end

function output = simulate_te_cck(cfg, simulationDir)
options = struct();
options.snrList = cfg.snrList;
options.frameWords = cfg.teFrameWords;
options.frameCount = cfg.teFrameCount;
options.turboIterations = cfg.turboIterations;
options.randomSeed = cfg.randomSeed + 1000;
options.minimumErrorsForPlot = cfg.minimumErrorsForPlot;
options.channelDelays = cfg.channelDelays;
options.channelPowerDb = cfg.channelPowerDb;
options.channelPhase = cfg.channelPhase;
options.pathDopplerPerChip = cfg.pathDopplerPerChip;
options.pathTimeCorrelation = 1;
options.pathFadingFraction = 0;
options.channelEstimateMode = "perfect";
options.outputDir = fullfile(cfg.outputDir, "fig5_27_internal_te");
output = scfde.simulate_chapter5_figure526(options, simulationDir);
end

function write_figure(result)
fig = figure("Color", "w", "Position", [120, 55, 980, 850], "Visible", "off");
ax = axes(fig, "Position", [0.16, 0.22, 0.73, 0.70]);
hold(ax, "on");
styles = {"-o", "-s", "--*", ":o", ":^", ":*", "-", ...
    "-<", "->", "-o", "-*", "-d"};
colors = [0.87, 0.18, 0.14; 0.35, 0.65, 0.24; 0.15, 0.34, 0.66; ...
    0.15, 0.34, 0.66; 0.64, 0.34, 0.62; 0.64, 0.34, 0.62; ...
    0.88, 0.18, 0.14; 0.04, 0.04, 0.04; 0.04, 0.04, 0.04; ...
    0.04, 0.04, 0.04; 0.04, 0.04, 0.04; 0.04, 0.04, 0.04];
for methodIndex = 1:numel(result.methodLabels)
    markerFace = "none";
    if ismember(methodIndex, [2, 4, 6, 10])
        markerFace = colors(methodIndex, :);
    end
    semilogy(ax, result.snrList, result.displayBer(methodIndex, :), ...
        styles{methodIndex}, "Color", colors(methodIndex, :), ...
        "LineWidth", 1.35, "MarkerSize", 8, ...
        "MarkerFaceColor", markerFace, ...
        "DisplayName", result.methodLabels(methodIndex));
end
box(ax, "on");
grid(ax, "on");
ax.YMinorGrid = "on";
ax.GridLineStyle = "--";
ax.MinorGridLineStyle = "--";
ax.GridAlpha = 0.30;
ax.MinorGridAlpha = 0.20;
ax.FontName = "Microsoft YaHei";
ax.FontSize = 10.2;
ax.LineWidth = 1;
ax.YScale = "log";
xlim(ax, [-5, 10]);
ylim(ax, [1e-5, 1]);
xticks(ax, -5:5:10);
yticks(ax, 10 .^ (-5:0));
yticklabels(ax, {"10^{-5}", "10^{-4}", "10^{-3}", "10^{-2}", ...
    "10^{-1}", "10^{0}"});
xlabel(ax, "SNR/dB");
ylabel(ax, "BER");
legend(ax, "Location", "southwest", "FontSize", 9.1, "NumColumns", 1);
annotation(fig, "textbox", [0.13, 0.055, 0.76, 0.055], "String", ...
    "图 5-27  水声信道下多种 CCK 接收机的 BER 性能比较", ...
    "EdgeColor", "none", "HorizontalAlignment", "center", ...
    "FontName", "Microsoft YaHei", "FontSize", 14);
exportgraphics(fig, result.figurePath, "Resolution", 220);
close(fig);
end

function write_table(result)
methodColumn = strings(0, 1);
snrColumn = zeros(0, 1);
berColumn = zeros(0, 1);
displayColumn = zeros(0, 1);
errorColumn = zeros(0, 1);
bitColumn = zeros(0, 1);
for methodIndex = 1:numel(result.methodLabels)
    count = numel(result.snrList);
    methodColumn = [methodColumn; repmat(result.methodLabels(methodIndex), count, 1)];
    snrColumn = [snrColumn; result.snrList(:)];
    berColumn = [berColumn; result.ber(methodIndex, :).'];
    displayColumn = [displayColumn; result.displayBer(methodIndex, :).'];
    errorColumn = [errorColumn; result.errorCounts(methodIndex, :).'];
    bitColumn = [bitColumn; result.bitTotals(methodIndex, :).'];
end
writetable(table(methodColumn, snrColumn, berColumn, displayColumn, errorColumn, ...
    bitColumn, 'VariableNames', {'Method', 'SNR_dB', 'BER', 'DisplayBER', ...
    'ErrorCount', 'BitTotal'}), result.csvPath);
end

function output = merge_options_local(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end

function output = simulate_dynamic_rsse(cfg, channel)
% Four-state RSSE with a dynamic decision-feedback tail per survivor.
[book, bitTable] = make_fr_cck_book();
wordLength = size(book, 2);
bitCount = size(bitTable, 2);
memory = numel(channel) - 1;
tailKey = [round(real(book(:, end)) * 1e12), ...
    round(imag(book(:, end)) * 1e12)];
[~, ~, stateForWord] = unique(tailKey, "rows");
stateCount = max(stateForWord);
assert(stateCount == cfg.rsseStateCount, "SCFDE:UnexpectedRsseStates", ...
    "The FR-CCK RSSE state grouping must contain four final-chip phases.");

rng(cfg.randomSeed + 527, "twister");
snrCount = numel(cfg.snrList);
output.ber = zeros(1, snrCount);
output.errorCounts = zeros(1, snrCount);
output.bitTotals = zeros(1, snrCount);
output.frameErrorCounts = zeros(1, snrCount);
output.frameTotals = zeros(1, snrCount);
wordEnergy = mean(sum(abs(book).^2, 2));
for snrIndex = 1:snrCount
    errorCount = 0;
    bitTotal = 0;
    frameErrorCount = 0;
    noiseVariance = wordEnergy / bitCount * 10^(-cfg.snrList(snrIndex) / 10);
    for frameIndex = 1:cfg.frontEndFrameCount
        transmittedIndices = randi(size(book, 1), 1, cfg.frontEndWords);
        transmittedChips = reshape(book(transmittedIndices, :).', 1, []);
        clean = filter(channel, 1, [transmittedChips, zeros(1, memory)]);
        received = clean + sqrt(noiseVariance / 2) * ...
            (randn(size(clean)) + 1j * randn(size(clean)));
        detectedIndices = dynamic_rsse_detect(received, book, stateForWord, channel);
        bitErrors = bitTable(detectedIndices, :) ~= bitTable(transmittedIndices, :);
        errorCount = errorCount + sum(bitErrors, "all");
        bitTotal = bitTotal + cfg.frontEndWords * bitCount;
        frameErrorCount = frameErrorCount + any(bitErrors, "all");
    end
    output.ber(snrIndex) = errorCount / bitTotal;
    output.errorCounts(snrIndex) = errorCount;
    output.bitTotals(snrIndex) = bitTotal;
    output.frameErrorCounts(snrIndex) = frameErrorCount;
    output.frameTotals(snrIndex) = cfg.frontEndFrameCount;
end
output.stateCount = stateCount;
output.stateForWord = stateForWord.';
end

function detected = dynamic_rsse_detect(received, book, stateForWord, channel)
wordLength = size(book, 2);
memory = numel(channel) - 1;
blockCount = (numel(received) - memory) / wordLength;
assert(blockCount == floor(blockCount) && blockCount > 0, ...
    "SCFDE:InvalidRsseFrame", "The received RSSE frame has an invalid length.");
stateCount = max(stateForWord);
pathMetric = inf(1, stateCount);
survivorTail = complex(zeros(stateCount, memory));
predecessor = zeros(blockCount, stateCount);
survivor = zeros(blockCount, stateCount);

for blockIndex = 1:blockCount
    observation = received((blockIndex - 1) * wordLength + (1:wordLength));
    nextMetric = inf(1, stateCount);
    nextTail = complex(zeros(stateCount, memory));
    for candidate = 1:size(book, 1)
        nextState = stateForWord(candidate);
        if blockIndex == 1
            predicted = rsse_expected_block(zeros(1, memory), book(candidate, :), channel);
            metric = sum(abs(observation - predicted).^2);
            if metric < nextMetric(nextState)
                nextMetric(nextState) = metric;
                nextTail(nextState, :) = rsse_feedback_tail(zeros(1, memory), ...
                    book(candidate, :), memory);
                survivor(blockIndex, nextState) = candidate;
            end
            continue;
        end
        for previousState = 1:stateCount
            if ~isfinite(pathMetric(previousState))
                continue;
            end
            predicted = rsse_expected_block(survivorTail(previousState, :), ...
                book(candidate, :), channel);
            metric = pathMetric(previousState) + sum(abs(observation - predicted).^2);
            if metric < nextMetric(nextState)
                nextMetric(nextState) = metric;
                nextTail(nextState, :) = rsse_feedback_tail( ...
                    survivorTail(previousState, :), book(candidate, :), memory);
                predecessor(blockIndex, nextState) = previousState;
                survivor(blockIndex, nextState) = candidate;
            end
        end
    end
    pathMetric = nextMetric;
    survivorTail = nextTail;
end

[~, state] = min(pathMetric);
detected = zeros(1, blockCount);
for blockIndex = blockCount:-1:1
    detected(blockIndex) = survivor(blockIndex, state);
    if blockIndex > 1
        state = predecessor(blockIndex, state);
    end
end
end

function output = rsse_expected_block(previousTail, word, channel)
memory = numel(channel) - 1;
convolution = conv([previousTail, word], channel);
output = convolution(memory + 1:memory + numel(word));
end

function tail = rsse_feedback_tail(previousTail, word, memory)
history = [previousTail, word];
tail = history(end - memory + 1:end);
end

function [book, bits] = make_fr_cck_book()
bits = zeros(256, 8);
book = complex(zeros(256, 8));
for wordIndex = 0:255
    wordBits = bitget(wordIndex, 1:8);
    bits(wordIndex + 1, :) = wordBits;
    phase = [pi / 4 + pi / 2 * (wordBits(1) + 2 * wordBits(2)), ...
        pi / 2 * (wordBits(3) + 2 * wordBits(4)), ...
        pi / 2 * (wordBits(5) + 2 * wordBits(6)), ...
        pi / 2 * (wordBits(7) + 2 * wordBits(8))];
    phi1 = phase(1); phi2 = phase(2); phi3 = phase(3); phi4 = phase(4);
    word = exp(1j * [phi1 + phi2 + phi3 + phi4, phi1 + phi3 + phi4, ...
        phi1 + phi2 + phi4, phi1 + phi4, phi1 + phi2 + phi3, ...
        phi1 + phi3, phi1 + phi2, phi1]);
    word([4, 7]) = -word([4, 7]);
    book(wordIndex + 1, :) = word / sqrt(8);
end
end
