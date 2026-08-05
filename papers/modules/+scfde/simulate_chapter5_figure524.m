function result = simulate_chapter5_figure524(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE524 Compare DSSS and iterative CCK receivers.
if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrList = -5:10;
defaults.frameWords = 48;
defaults.frameCount = 64;
defaults.turboIterations = 4;
defaults.turboDamping = 0.50;
defaults.minimumErrorsForPlot = 5;
defaults.randomSeed = 20260808;
defaults.channel = comparison_multipath_channel();
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options_local(defaults, options);
cfg.channel = cfg.channel(:).';
cfg.channel = cfg.channel / norm(cfg.channel);

methodLabels = ["CCK-Rake", "TE-CCK-閺冪姾鍑禒?, "TE-CCK-1濞喡ゅ嚡娴?, ...
    "TE-CCK-2濞喡ゅ嚡娴?, "TE-CCK-3濞喡ゅ嚡娴?, "TE-CCK-4濞喡ゅ嚡娴?, ...
    "DSSS-2", "DSSS-4", "DSSS-8"];
methodCount = numel(methodLabels);
snrCount = numel(cfg.snrList);
errorCounts = zeros(methodCount, snrCount);
bitTotals = zeros(methodCount, snrCount);
[book, bits] = cck8_codebook();

for snrIndex = 1:snrCount
    rng(cfg.randomSeed + snrIndex, "twister");
    errors = zeros(methodCount, 1);
    totals = zeros(methodCount, 1);
    for frameIndex = 1:cfg.frameCount
        frame = cck_repetition_frame(book, bits, cfg.channel, ...
            cfg.snrList(snrIndex), cfg.frameWords);
        rakeDetected = cck_rake_detect(frame, book, cfg.channel);
        rakeBits = reshape(bits(rakeDetected, :).', 1, []);
        rakeInformation = decode_repetition_bits(rakeBits, frame);
        informationHistory = te_cck_detect(frame, book, bits, cfg.channel, ...
            cfg.turboIterations, cfg.turboDamping);
        errors(1) = errors(1) + sum(rakeInformation ~= frame.informationBits);
        for iteration = 0:cfg.turboIterations
            errors(iteration + 2) = errors(iteration + 2) + ...
                sum(informationHistory(iteration + 1, :) ~= frame.informationBits);
        end
        cckTotal = numel(frame.informationBits);
        totals(1:6) = totals(1:6) + cckTotal;
        for spreadingIndex = 1:3
            spreading = 2^spreadingIndex;
            [dsssErrors, dsssTotal] = dsss_rake_frame(cfg.channel, ...
                cfg.snrList(snrIndex), spreading, cfg.frameWords * 4);
            errors(6 + spreadingIndex) = errors(6 + spreadingIndex) + dsssErrors;
            totals(6 + spreadingIndex) = totals(6 + spreadingIndex) + dsssTotal;
        end
    end
    errorCounts(:, snrIndex) = errors;
    bitTotals(:, snrIndex) = totals;
end

ber = errorCounts ./ bitTotals;
plotBer = ber;
for methodIndex = 1:methodCount
    firstUnreliable = find(errorCounts(methodIndex, :) < cfg.minimumErrorsForPlot, 1);
    if ~isempty(firstUnreliable)
        plotBer(methodIndex, firstUnreliable:end) = nan;
    end
end
result.config = cfg;
result.methodLabels = methodLabels;
result.snrList = cfg.snrList;
result.ber = ber;
result.plotBer = plotBer;
result.errorCounts = errorCounts;
result.bitTotals = bitTotals;
result.minimumErrorsForPlot = cfg.minimumErrorsForPlot;

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
figurePath = fullfile(cfg.outputDir, "fig5_24_dsss_cck_ber.png");
matPath = fullfile(cfg.outputDir, "fig5_24_dsss_cck_ber.mat");
csvPath = fullfile(cfg.outputDir, "fig5_24_dsss_cck_ber.csv");
fig = figure("Color", "w", "Position", [120, 55, 980, 860], "Visible", "off");
ax = axes(fig, "Position", [0.16, 0.22, 0.73, 0.70]);
hold(ax, "on");
colors = [0.16, 0.45, 0.72; 0.85, 0.33, 0.10; 0.49, 0.18, 0.56; ...
    0.00, 0.52, 0.45; 0.91, 0.66, 0.05; 0.75, 0.20, 0.38; ...
    0.30, 0.30, 0.30; 0.36, 0.55, 0.18; 0.12, 0.55, 0.78];
markers = {"o", "<", ">", "s", "p", "d", "o", "s", "*"};
lineStyles = {"-", "-", "-", "-", "-", "-", "--", "--", "--"};
for methodIndex = 1:methodCount
    markerFaceColor = 'w';
    if methodIndex == 5 || methodIndex == 9
        markerFaceColor = colors(methodIndex, :);
    end
    plot(ax, cfg.snrList, log10(plotBer(methodIndex, :)), ...
        "Color", colors(methodIndex, :), "LineStyle", lineStyles{methodIndex}, ...
        "LineWidth", 1.15, "Marker", markers{methodIndex}, "MarkerSize", 7, ...
        "MarkerFaceColor", markerFaceColor, "DisplayName", methodLabels(methodIndex));
end
box(ax, "on");
grid(ax, "on");
ax.YMinorGrid = "on";
ax.GridLineStyle = "--";
ax.MinorGridLineStyle = "--";
ax.GridAlpha = 0.32;
ax.MinorGridAlpha = 0.22;
ax.FontName = "Microsoft YaHei";
ax.FontSize = 10.5;
ax.LineWidth = 1;
xlim(ax, [-5, 10]);
ylim(ax, [-6, 0]);
xticks(ax, -5:5:10);
yticks(ax, -6:0);
yticklabels(ax, {"10^{-6}", "10^{-5}", "10^{-4}", "10^{-3}", ...
    "10^{-2}", "10^{-1}", "10^{0}"});
xlabel(ax, "SNR (dB)");
ylabel(ax, "鐠囶垳鐖滈悳?);
legend(ax, "Location", "southwest", "FontSize", 9.4, "NumColumns", 1);
annotation(fig, "textbox", [0.13, 0.055, 0.76, 0.055], "String", ...
    "閸?5-24  娴犺法婀℃穱锟犱壕娑?DSSS 閸?CCK 閻?BER 閹嗗厴濮ｆ棁绶?, ...
    "EdgeColor", "none", "HorizontalAlignment", "center", ...
    "FontName", "Microsoft YaHei", "FontSize", 14);
exportgraphics(fig, figurePath, "Resolution", 220);
close(fig);

methodColumn = strings(0, 1);
snrColumn = zeros(0, 1);
berColumn = zeros(0, 1);
plotBerColumn = zeros(0, 1);
errorColumn = zeros(0, 1);
bitColumn = zeros(0, 1);
for methodIndex = 1:methodCount
    methodColumn = [methodColumn; repmat(methodLabels(methodIndex), snrCount, 1)];
    snrColumn = [snrColumn; cfg.snrList(:)];
    berColumn = [berColumn; ber(methodIndex, :).'];
    plotBerColumn = [plotBerColumn; plotBer(methodIndex, :).'];
    errorColumn = [errorColumn; errorCounts(methodIndex, :).'];
    bitColumn = [bitColumn; bitTotals(methodIndex, :).'];
end
writetable(table(methodColumn, snrColumn, berColumn, plotBerColumn, errorColumn, ...
    bitColumn, 'VariableNames', {'Method', 'SNR_dB', 'BER', 'DisplayBER', ...
    'ErrorCount', 'BitTotal'}), csvPath);
result.figurePath = figurePath;
result.matPath = matPath;
result.csvPath = csvPath;
save(matPath, "result", "cfg");
end

function frame = cck_repetition_frame(book, bits, channel, snrDb, wordCount)
bitCount = size(bits, 2);
codedLength = wordCount * bitCount;
informationLength = codedLength / 2;
frame.informationBits = randi([0, 1], 1, informationLength);
positions = randperm(codedLength);
frame.firstCopy = positions(1:informationLength);
secondCopy = positions(informationLength + 1:end);
interleaver = randperm(informationLength);
frame.codedBits = zeros(1, codedLength);
frame.codedBits(frame.firstCopy) = frame.informationBits;
frame.codedBits(secondCopy) = frame.informationBits(interleaver);
inverseInterleaver = zeros(1, informationLength);
inverseInterleaver(interleaver) = 1:informationLength;
frame.pairedPosition = zeros(1, codedLength);
frame.pairedPosition(frame.firstCopy) = secondCopy(inverseInterleaver);
frame.pairedPosition(secondCopy) = frame.firstCopy(interleaver);
wordBits = reshape(frame.codedBits, bitCount, []).';
frame.indices = 1 + wordBits * (2 .^ (0:bitCount - 1)).';
frame.chips = reshape(book(frame.indices, :).', [], 1);
energyPerInformationBit = 1 / (bitCount / 2);
frame.noiseVariance = energyPerInformationBit * 10^(-snrDb / 10);
memory = numel(channel) - 1;
frame.received = filter(channel, 1, [frame.chips; zeros(memory, 1)]) + ...
    sqrt(frame.noiseVariance / 2) * ...
    (randn(numel(frame.chips) + memory, 1) + ...
    1j * randn(numel(frame.chips) + memory, 1));
end

function detected = cck_rake_detect(frame, book, channel)
wordLength = size(book, 2);
blockCount = numel(frame.indices);
padded = [frame.received; zeros(numel(channel), 1)];
combined = complex(zeros(blockCount, wordLength));
for block = 1:blockCount
    start = (block - 1) * wordLength + 1;
    for tap = 1:numel(channel)
        combined(block, :) = combined(block, :) + conj(channel(tap)) * ...
            padded(start + tap - 1:start + tap + wordLength - 2).';
    end
end
combined = combined / sum(abs(channel).^2);
detected = nearest_book(combined, book);
end

function informationHistory = te_cck_detect(frame, book, bits, channel, iterations, damping)
channel = channel(:);
wordLength = size(book, 2);
bitCount = size(bits, 2);
blockCount = numel(frame.indices);
frameLength = blockCount * wordLength;
received = frame.received(1:frameLength);
H = fft([channel; zeros(frameLength - numel(channel), 1)]);
Y = fft(received);
soft = complex(zeros(frameLength, 1));
prior = zeros(1, blockCount * bitCount);
informationHistory = false(iterations + 1, numel(frame.informationBits));
for iteration = 0:iterations
    reliability = min(0.98, wordLength * mean(abs(soft).^2));
    equalizer = conj(H) ./ (frame.noiseVariance + ...
        (1 - reliability) * abs(H).^2);
    equalizer = equalizer / mean(equalizer .* H);
    feedback = equalizer .* H - 1;
    estimate = ifft(equalizer .* Y - feedback .* fft(soft));
    blocks = reshape(estimate, wordLength, []).';
    priorWords = reshape(prior, bitCount, []).';
    [~, softWord, posteriorLlr] = soft_book_detect(blocks, book, bits, ...
        frame.noiseVariance, priorWords);
    extrinsic = reshape(posteriorLlr.', 1, []) - prior;
    informationLlr = extrinsic(frame.firstCopy) + ...
        extrinsic(frame.pairedPosition(frame.firstCopy));
    informationHistory(iteration + 1, :) = informationLlr < 0;
    if iteration < iterations
        prior = damping * extrinsic(frame.pairedPosition);
        candidateSoft = reshape(softWord.', [], 1);
        soft = 0.65 * soft + 0.35 * candidateSoft;
    end
end
end

function [detected, softWord, posteriorLlr] = soft_book_detect( ...
        observations, book, bits, noiseVariance, priorWords)
blockCount = size(observations, 1);
bitCount = size(bits, 2);
detected = zeros(1, blockCount);
softWord = complex(zeros(size(observations)));
posteriorLlr = zeros(blockCount, bitCount);
for block = 1:blockCount
    distance = sum(abs(book - observations(block, :)).^2, 2);
    metric = -distance / max(noiseVariance, 1e-8) + ...
        0.5 * ((1 - 2 * bits) * priorWords(block, :).');
    [maximum, detected(block)] = max(metric);
    weights = exp(metric - maximum);
    weights = weights / sum(weights);
    softWord(block, :) = weights.' * book;
    for bit = 1:bitCount
        posteriorLlr(block, bit) = log_sum_exp(metric(bits(:, bit) == 0)) - ...
            log_sum_exp(metric(bits(:, bit) == 1));
    end
end
end

function [errors, total] = dsss_rake_frame(channel, snrDb, spreading, symbolCount)
bits = randi([0, 1], symbolCount, 2);
symbols = (1 - 2 * bits(:, 1) + 1j * (1 - 2 * bits(:, 2))) / sqrt(2);
pn = dsss_sequence(spreading);
chips = reshape((symbols * pn / sqrt(spreading)).', [], 1);
memory = numel(channel) - 1;
noiseVariance = 0.5 * 10^(-snrDb / 10);
received = filter(channel, 1, [chips; zeros(memory, 1)]) + ...
    sqrt(noiseVariance / 2) * ...
    (randn(numel(chips) + memory, 1) + ...
    1j * randn(numel(chips) + memory, 1));
referenceChips = [pn.' / sqrt(spreading); zeros(memory, 1)];
referenceReceived = filter(channel, 1, referenceChips);
if spreading < 8
    chipEstimate = received(1:numel(chips));
    referenceEstimate = referenceReceived(1:spreading);
else
    chipEstimate = rake_chip_combine([received; zeros(memory, 1)], channel, numel(chips));
    referenceEstimate = rake_chip_combine( ...
        [referenceReceived; zeros(memory, 1)], channel, spreading);
end
gain = sum(referenceEstimate .* pn.') / sqrt(spreading);
estimate = reshape(chipEstimate, spreading, []).' * pn.' / sqrt(spreading) / gain;
detectedBits = [real(estimate) < 0, imag(estimate) < 0];
errors = sum(sum(detectedBits ~= bits));
total = numel(bits);
end

function chipEstimate = rake_chip_combine(received, channel, chipCount)
chipEstimate = complex(zeros(chipCount, 1));
for chip = 1:chipCount
    for tap = 1:numel(channel)
        chipEstimate(chip) = chipEstimate(chip) + conj(channel(tap)) * ...
            received(chip + tap - 1);
    end
end
chipEstimate = chipEstimate / sum(abs(channel).^2);
end

function sequence = dsss_sequence(spreading)
switch spreading
    case 2
        sequence = [1, -1];
    case 4
        sequence = [1, -1, -1, 1];
    case 8
        sequence = [1, 1, 1, -1, 1, -1, -1, -1];
    otherwise
        error("SCFDE:UnsupportedSpreading", "Supported spreading lengths are 2, 4, and 8.");
end
end

function informationBits = decode_repetition_bits(codedBits, frame)
informationBits = codedBits(frame.firstCopy);
pairedBits = codedBits(frame.pairedPosition(frame.firstCopy));
agreement = informationBits == pairedBits;
informationBits(agreement) = pairedBits(agreement);
end

function value = log_sum_exp(values)
maximum = max(values);
value = maximum + log(sum(exp(values - maximum)));
end

function detected = nearest_book(observations, book)
metric = sum(abs(observations).^2, 2) + sum(abs(book).^2, 2).' - ...
    2 * real(observations * book');
[~, detected] = min(metric, [], 2);
detected = detected.';
end

function [book, bits] = cck8_codebook()
book = complex(zeros(256, 8));
bits = zeros(256, 8);
for index = 0:255
    rowBits = bitget(index, 1:8);
    bits(index + 1, :) = rowBits;
    qpsk = @(pair) pi * pair(1) + 0.5 * pi * pair(2);
    phase = [qpsk(rowBits(1:2)), qpsk(rowBits(3:4)), ...
        qpsk(rowBits(5:6)), qpsk(rowBits(7:8))];
    word = exp(1j * [phase(1) + phase(2) + phase(3) + phase(4), ...
        phase(1) + phase(3) + phase(4), phase(1) + phase(2) + phase(4), ...
        phase(1) + phase(4), phase(1) + phase(2) + phase(3), ...
        phase(1) + phase(3), phase(1) + phase(2), phase(1)]);
    word([4, 7]) = -word([4, 7]);
    book(index + 1, :) = word / sqrt(8);
end
end

function channel = short_turbo_channel()
channel = [1, 0.70 * exp(1j * 0.4), 0.50 * exp(-1j * 0.8), ...
    0.28 * exp(1j * 1.4), 0.15 * exp(-1j * 2.1)];
channel = channel / norm(channel);
end

function channel = comparison_multipath_channel()
delays = [0, 1, 2, 3, 4, 5, 7, 9, 11, 13, 15];
power = exp(-delays / 5.5);
phase = [0, 0.5, -1.0, 0.8, -2.1, 0.25, -1.5, 1.4, -0.8, 0.9, -2.6];
channel = complex(zeros(1, delays(end) + 1));
channel(delays + 1) = sqrt(power) .* exp(1j * phase);
channel = channel / norm(channel);
end

function output = merge_options_local(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
