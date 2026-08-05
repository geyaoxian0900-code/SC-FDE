function result = simulate_chapter5_figure530(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE530 Compare receive-array sizes for CCK-IBDFE.
%   A four-transmit-antenna spatial-modulation frame is observed by 2, 3,
%   or 4 receive elements.  QPSK and CCK both include the active-antenna
%   index bits in BER and use the same channel realization and Eb/N0.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrList = -4:2:14;
defaults.transmitCount = 4;
defaults.receiveCounts = [2, 3, 4];
defaults.wordsPerFrame = 96;
defaults.frameCount = 64;
defaults.cpLength = 8;
defaults.qpskIterations = 1;
defaults.cckIterations = 5;
defaults.cckDamping = 0.58;
defaults.randomSeed = 20260803;
defaults.channelSeed = 20260830;
defaults.pathPower = [1, .65, .42, .30, .20, .12];
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options(defaults, options);
validate_config(cfg);

[qpskBook, qpskBits] = make_qpsk_book();
[cckBook, cckBits] = make_cck_book();
indexBits = log2(cfg.transmitCount);
qpskBook = qpskBook * sqrt(size(qpskBits, 2) + indexBits);
cckBook = cckBook * sqrt(size(cckBits, 2) + indexBits);
channel = make_mimo_channel(cfg);
frameLength = cfg.wordsPerFrame * size(cckBook, 2);
response = mimo_frequency_response(channel, frameLength);

methodLabels = strings(1, 2 * numel(cfg.receiveCounts));
for index = 1:numel(cfg.receiveCounts)
    receiveCount = cfg.receiveCounts(index);
    methodLabels(2 * index - 1) = "N_r = " + string(receiveCount) + ", QPSK";
    methodLabels(2 * index) = "N_r = " + string(receiveCount) + ", CCK-IBDFE";
end

rng(cfg.randomSeed, "twister");
snrCount = numel(cfg.snrList);
methodCount = numel(methodLabels);
errorCounts = zeros(methodCount, snrCount);
bitTotals = zeros(methodCount, snrCount);
for snrIndex = 1:snrCount
    errors = zeros(methodCount, 1);
    totals = zeros(methodCount, 1);
    for frameIndex = 1:cfg.frameCount
        qpskFrame = make_spatial_frame(qpskBook, qpskBits, cfg, ...
            channel, cfg.snrList(snrIndex));
        cckFrame = make_spatial_frame(cckBook, cckBits, cfg, ...
            channel, cfg.snrList(snrIndex));
        for receiveIndex = 1:numel(cfg.receiveCounts)
            receiveCount = cfg.receiveCounts(receiveIndex);
            qpskOutput = mimo_ibdfe_receive(qpskFrame, qpskBook, qpskBits, ...
                response(1:receiveCount, :, :), cfg.qpskIterations, 0);
            cckOutput = mimo_ibdfe_receive(cckFrame, cckBook, cckBits, ...
                response(1:receiveCount, :, :), cfg.cckIterations, ...
                cfg.cckDamping);
            methodIndex = 2 * receiveIndex - 1;
            errors(methodIndex) = errors(methodIndex) + qpskOutput.bitErrors(end);
            errors(methodIndex + 1) = errors(methodIndex + 1) + ...
                cckOutput.bitErrors(end);
            totals(methodIndex) = totals(methodIndex) + qpskOutput.bitTotal;
            totals(methodIndex + 1) = totals(methodIndex + 1) + cckOutput.bitTotal;
        end
    end
    errorCounts(:, snrIndex) = errors;
    bitTotals(:, snrIndex) = totals;
end

ber = errorCounts ./ bitTotals;
displayBer = ber;
displayBer(errorCounts == 0) = 0.5 ./ bitTotals(errorCounts == 0);

result.config = cfg;
result.channel = channel;
result.qpskBook = qpskBook;
result.cckBook = cckBook;
result.methodLabels = methodLabels;
result.snrList = cfg.snrList;
result.ber = ber;
result.displayBer = displayBer;
result.errorCounts = errorCounts;
result.bitTotals = bitTotals;
result.zeroErrorDisplayConvention = "0.5 / BitTotal";
result.systemDefinition = struct( ...
    "transmitArray", "4娑擃亜褰傜亸鍕█閸忓喛绱濋崡鏇熺负濞茶崵鈹栭梻纾嬬殶閸?, ...
    "receiveArrays", cfg.receiveCounts, ...
    "qpskReceiver", "娑撯偓鏉炵攨IMO-MMSE妫版垵鐓欏Λ鈧ù?, ...
    "cckReceiver", "娴滄棁鐤嗛懕鏂挎値缁屾椽妫跨槐銏犵穿閸滃苯鐣弫纰圕K閻礁鐡ч崥搴ㄧ崣IBDFE", ...
    "channelKnowledge", "perfect", ...
    "snrDefinition", "Eb/N0閿涘本鐦℃穱鈩冧紖濮ｆ梻澹掗懗浠嬪櫤Eb=1");

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
result.figurePath = fullfile(cfg.outputDir, "fig5_30_receive_elements_ber.png");
result.matPath = fullfile(cfg.outputDir, "fig5_30_receive_elements_ber.mat");
result.csvPath = fullfile(cfg.outputDir, "fig5_30_receive_elements_ber.csv");
write_figure(result);
write_table(result);
save(result.matPath, "result", "cfg");
end

function validate_config(cfg)
validateattributes(cfg.transmitCount, {'numeric'}, ...
    {'scalar', 'integer', '>=', 2});
assert(log2(cfg.transmitCount) == round(log2(cfg.transmitCount)), ...
    "SCFDE:Figure530TransmitCount", "transmitCount must be a power of two.");
validateattributes(cfg.receiveCounts, {'numeric'}, ...
    {'vector', 'integer', '>=', 1});
assert(all(diff(cfg.receiveCounts) > 0), "SCFDE:Figure530ReceiveCounts", ...
    "receiveCounts must be strictly increasing.");
validateattributes(cfg.wordsPerFrame, {'numeric'}, ...
    {'scalar', 'integer', '>=', 8});
validateattributes(cfg.frameCount, {'numeric'}, ...
    {'scalar', 'integer', '>=', 1});
validateattributes(cfg.cpLength, {'numeric'}, ...
    {'scalar', 'integer', '>=', numel(cfg.pathPower) - 1});
assert(max(cfg.receiveCounts) == cfg.transmitCount, ...
    "SCFDE:Figure530ArrayGeometry", ...
    "The Figure 5-30 comparison uses N_r=2,3,4 for four transmit elements.");
end

function [book, bits] = make_qpsk_book()
bits = [0, 0; 1, 0; 0, 1; 1, 1];
symbols = (1 - 2 * bits(:, 1) + 1j * (1 - 2 * bits(:, 2))) / sqrt(2);
book = repmat(symbols, 1, 8) / sqrt(8);
end

function [book, bits] = make_cck_book()
bits = zeros(256, 8);
book = complex(zeros(256, 8));
for value = 0:255
    rowBits = bitget(value, 1:8);
    bits(value + 1, :) = rowBits;
    qpsk = @(pair) pi * pair(1) + 0.5 * pi * pair(2);
    phase = [qpsk(rowBits(1:2)), qpsk(rowBits(3:4)), ...
        qpsk(rowBits(5:6)), qpsk(rowBits(7:8))];
    word = exp(1j * [phase(1) + phase(2) + phase(3) + phase(4), ...
        phase(1) + phase(3) + phase(4), ...
        phase(1) + phase(2) + phase(4), ...
        phase(1) + phase(4), ...
        phase(1) + phase(2) + phase(3), ...
        phase(1) + phase(3), phase(1) + phase(2), phase(1)]);
    word([4, 7]) = -word([4, 7]);
    book(value + 1, :) = word / sqrt(8);
end
end

function channel = make_mimo_channel(cfg)
randomState = rng;
rng(cfg.channelSeed, "twister");
tapCount = numel(cfg.pathPower);
channel = complex(zeros(cfg.transmitCount, cfg.transmitCount, tapCount));
for receive = 1:cfg.transmitCount
    for transmit = 1:cfg.transmitCount
        channel(receive, transmit, :) = sqrt(cfg.pathPower / ...
            (2 * cfg.transmitCount)) .* ...
            (randn(1, tapCount) + 1j * randn(1, tapCount));
    end
end
rng(randomState);
end

function response = mimo_frequency_response(channel, frameLength)
[receiveCount, transmitCount, tapCount] = size(channel);
response = complex(zeros(receiveCount, transmitCount, frameLength));
for receive = 1:receiveCount
    for transmit = 1:transmitCount
        impulse = [squeeze(channel(receive, transmit, :)).', ...
            zeros(1, frameLength - tapCount)];
        response(receive, transmit, :) = fft(impulse);
    end
end
end

function frame = make_spatial_frame(book, bits, cfg, channel, snrDb)
wordLength = size(book, 2);
frameLength = cfg.wordsPerFrame * wordLength;
indices = randi(size(book, 1), 1, cfg.wordsPerFrame);
activeAntenna = randi(cfg.transmitCount, 1, cfg.wordsPerFrame);
transmitted = complex(zeros(cfg.transmitCount, frameLength));
for word = 1:cfg.wordsPerFrame
    positions = (word - 1) * wordLength + (1:wordLength);
    transmitted(activeAntenna(word), positions) = book(indices(word), :);
end
transmittedCp = [transmitted(:, end - cfg.cpLength + 1:end), transmitted];
receivedCp = complex(zeros(cfg.transmitCount, size(transmittedCp, 2)));
for receive = 1:cfg.transmitCount
    for transmit = 1:cfg.transmitCount
        receivedCp(receive, :) = receivedCp(receive, :) + filter( ...
            squeeze(channel(receive, transmit, :)).', 1, transmittedCp(transmit, :));
    end
end
noiseVariance = 10^(-snrDb / 10);
receivedCp = receivedCp + sqrt(noiseVariance / 2) * ...
    (randn(size(receivedCp)) + 1j * randn(size(receivedCp)));
frame.received = receivedCp(:, cfg.cpLength + (1:frameLength));
frame.indices = indices;
frame.activeAntenna = activeAntenna;
frame.noiseVariance = noiseVariance;
frame.wordLength = wordLength;
end

function output = mimo_ibdfe_receive(frame, book, bitTable, response, iterations, damping)
[receiveCount, transmitCount, frameLength] = size(response);
wordCount = numel(frame.indices);
signalEnergy = mean(sum(abs(book).^2, 2)) / size(book, 2);
perStreamEnergy = signalEnergy / transmitCount;
Y = fft(frame.received(1:receiveCount, :), [], 2);
soft = complex(zeros(transmitCount, frameLength));
output.bitErrors = zeros(1, iterations);
output.bitTotal = wordCount * (size(bitTable, 2) + log2(transmitCount));
for iteration = 1:iterations
    reliability = min(0.985, mean(abs(soft(:)).^2) / max(perStreamEnergy, eps));
    residualVariance = max(0.02 * perStreamEnergy, ...
        perStreamEnergy * (1 - reliability));
    equalized = complex(zeros(transmitCount, frameLength));
    effectiveVariance = zeros(1, frameLength);
    feedbackSpectrum = fft(soft, [], 2);
    for bin = 1:frameLength
        h = response(:, :, bin);
        c = (h' * h + frame.noiseVariance / residualVariance * ...
            eye(transmitCount)) \ h';
        b = c * h - eye(transmitCount);
        equalized(:, bin) = c * Y(:, bin) - b * feedbackSpectrum(:, bin);
        errorCovariance = frame.noiseVariance * (c * c') + ...
            residualVariance * (b * b');
        effectiveVariance(bin) = max(1e-6, real(trace(errorCovariance)) / transmitCount);
    end
    estimates = ifft(equalized, [], 2);
    [detectedAntenna, detectedIndex, newSoft] = spatial_word_detector( ...
        estimates, book, mean(effectiveVariance));
    if iteration == 1
        soft = newSoft;
    else
        soft = (1 - damping) * soft + damping * newSoft;
    end
    wordErrors = sum(bitTable(detectedIndex, :) ~= ...
        bitTable(frame.indices, :), "all");
    indexErrors = antenna_bit_errors(detectedAntenna, frame.activeAntenna, ...
        transmitCount);
    output.bitErrors(iteration) = wordErrors + indexErrors;
end
end

function [detectedAntenna, detectedIndex, soft] = spatial_word_detector( ...
        estimates, book, variance)
[transmitCount, frameLength] = size(estimates);
wordLength = size(book, 2);
wordCount = frameLength / wordLength;
bookCount = size(book, 1);
blocks = reshape(estimates, transmitCount, wordLength, wordCount);
observationEnergy = squeeze(sum(sum(abs(blocks).^2, 1), 2));
metric = zeros(wordCount, bookCount, transmitCount);
bookEnergy = sum(abs(book).^2, 2).';
for antenna = 1:transmitCount
    observations = squeeze(blocks(antenna, :, :)).';
    metric(:, :, antenna) = observationEnergy + bookEnergy - ...
        2 * real(observations * book');
end
flattened = reshape(metric, wordCount, []);
[minimum, selected] = min(flattened, [], 2);
detectedAntenna = ceil(selected / bookCount).';
detectedIndex = mod(selected - 1, bookCount) + 1;
detectedIndex = detectedIndex.';
weights = exp(-(flattened - minimum) / max(variance, 1e-6));
weights = weights ./ sum(weights, 2);
soft = complex(zeros(transmitCount, frameLength));
for antenna = 1:transmitCount
    candidateRange = (antenna - 1) * bookCount + (1:bookCount);
    softBlocks = weights(:, candidateRange) * book;
    positions = reshape(softBlocks.', 1, []);
    soft(antenna, :) = positions;
end
end

function errors = antenna_bit_errors(detected, transmitted, antennaCount)
bitCount = log2(antennaCount);
detectedBits = zeros(numel(detected), bitCount);
transmittedBits = zeros(numel(transmitted), bitCount);
for bit = 1:bitCount
    detectedBits(:, bit) = bitget(detected(:) - 1, bit);
    transmittedBits(:, bit) = bitget(transmitted(:) - 1, bit);
end
errors = sum(detectedBits ~= transmittedBits, "all");
end

function write_figure(result)
fig = figure("Color", "w", "Position", [105, 55, 980, 820], "Visible", "off");
ax = axes(fig, "Position", [0.14, 0.22, 0.76, 0.70]);
hold(ax, "on");
blue = [0.08, 0.29, 0.58];
black = [0.05, 0.05, 0.05];
red = [0.86, 0.15, 0.12];
colors = [blue; blue; black; black; red; red];
styles = {"-s", "-^", "-.s", "-.^", "--s", "--^"};
for methodIndex = 1:numel(result.methodLabels)
    semilogy(ax, result.snrList, result.displayBer(methodIndex, :), ...
        styles{methodIndex}, "Color", colors(methodIndex, :), ...
        "LineWidth", 1.8, "MarkerSize", 9, "MarkerFaceColor", "none", ...
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
ax.FontSize = 11;
ax.LineWidth = 1;
ax.YScale = "log";
ax.YDir = "normal";
xlim(ax, [min(result.snrList), max(result.snrList)]);
ylim(ax, [1e-5, 1]);
xticks(ax, result.snrList);
yticks(ax, 10 .^ (-5:0));
yticklabels(ax, {"10^{-5}", "10^{-4}", "10^{-3}", "10^{-2}", ...
    "10^{-1}", "10^{0}"});
xlabel(ax, "E_b/N_0 / dB");
ylabel(ax, "鐠囶垳鐖滈悳?BER");
legend(ax, "Location", "northeast", "FontSize", 10.5, "NumColumns", 1);
annotation(fig, "textbox", [0.12, 0.055, 0.78, 0.055], "String", ...
    "閸?5-30  娑撳秴鎮撻幒銉︽暪闂冮潧鍘撴稉顏呮殶閻ㄥ嫯顕ら惍浣哄芳閹嗗厴鐎佃鐦?, ...
    "EdgeColor", "none", "HorizontalAlignment", "center", ...
    "FontName", "Microsoft YaHei", "FontSize", 15);
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
    bitColumn, 'VariableNames', {'Method', 'EbN0_dB', 'BER', 'DisplayBER', ...
    'ErrorCount', 'BitTotal'}), result.csvPath);
end

function output = merge_options(defaults, options)
output = defaults;
for name = string(fieldnames(options)).'
    output.(name) = options.(name);
end
end
