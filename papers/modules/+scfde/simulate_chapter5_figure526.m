function result = simulate_chapter5_figure526(options, simulationDir)
%SIMULATE_CHAPTER5_FIGURE526 DSSS and CCK BER over a time-varying UWA channel.
%   The compared schemes share an Eb/N0 definition and the same sparse
%   time-varying multipath model. CCK uses an LS channel estimate, a Rake
%   baseline, and a repetition-assisted frequency-domain turbo equalizer.
%   DSSS uses an explicit matched-finger Rake followed by despreading.

if nargin < 1 || isempty(options)
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
end

defaults.snrList = -5:10;
defaults.frameWords = 96;
defaults.frameCount = 48;
defaults.turboIterations = 4;
defaults.turboDamping = 0.72;
defaults.ldpcDecoderIterations = 18;
defaults.teCckLlrScale = 1;
defaults.cckBitInterleaving = true;
defaults.trainingLength = 127;
defaults.channelEstimateMode = "ls";
defaults.minimumErrorsForPlot = 3;
defaults.randomSeed = 20260803;
defaults.channelDelays = [0, 1, 3, 5, 8, 12, 16];
defaults.channelPowerDb = [0, -1.7, -3.8, -6.2, -9.0, -12.4, -16.0];
defaults.channelPhase = [0, 0.48, -1.15, 0.76, -2.06, 1.37, -2.58];
defaults.pathDopplerPerChip = [0, 0.000007, -0.000011, 0.000016, ...
    -0.000020, 0.000024, -0.000028];
defaults.pathTimeCorrelation = 0.99995;
defaults.pathFadingFraction = 0.06;
defaults.outputDir = fullfile(simulationDir, "chapter5_simulation", "results");
cfg = merge_options_local(defaults, options);
validate_config(cfg);
ensure_ldpc_path(simulationDir);

methodLabels = ["CCK-Rake", "TE-CCK-iter0", ...
    "TE-CCK-iter1", "TE-CCK-iter2", ...
    "TE-CCK-iter3", "TE-CCK-iter4", ...
    "DSSS-2", "DSSS-4", "DSSS-8"];
methodCount = numel(methodLabels);
snrCount = numel(cfg.snrList);
errorCounts = zeros(methodCount, snrCount);
bitTotals = zeros(methodCount, snrCount);
frameErrorCounts = zeros(methodCount, snrCount);
frameTotals = zeros(methodCount, snrCount);
[book, bitLabels] = cck8_codebook();
ldpcCode = scfde_make_ldpc(cfg.frameWords * size(bitLabels, 2) / 2);

for snrIndex = 1:snrCount
    errors = zeros(methodCount, 1);
    totals = zeros(methodCount, 1);
    frameErrors = zeros(methodCount, 1);
    frameTotal = 0;
    for frameIndex = 1:cfg.frameCount
        baseSeed = cfg.randomSeed + 100000 * snrIndex + 100 * frameIndex;

        cckFrame = make_cck_frame(book, bitLabels, cfg.frameWords, ldpcCode, ...
            cfg.cckBitInterleaving, baseSeed + 1);
        cckEnergyPerInformationBit = 1 / (size(bitLabels, 2) / 2);
        cckChannel = propagate_uwa_frame(cckFrame.chips, ...
            cckEnergyPerInformationBit, cfg.snrList(snrIndex), cfg, baseSeed + 2);

        rakeWords = cck_rake_detect(cckChannel.receivedData, book, cckChannel.hHat);
        rakeTransmittedBits = reshape(bitLabels(rakeWords, :).', 1, []);
        rakeBits = deinterleave_llr_or_bits(rakeTransmittedBits, cckFrame.interleaver);
        rakeInformation = ldpc_hard_decode(rakeBits, ldpcCode);
        errors(1) = errors(1) + sum(rakeInformation ~= cckFrame.informationBits);
        totals(1) = totals(1) + numel(cckFrame.informationBits);
        frameErrors(1) = frameErrors(1) + any(rakeInformation ~= cckFrame.informationBits);

        informationHistory = te_cck_detect(cckChannel, cckFrame, book, bitLabels, ...
            ldpcCode, cfg);
        for iteration = 0:cfg.turboIterations
            methodIndex = iteration + 2;
            errors(methodIndex) = errors(methodIndex) + sum( ...
                informationHistory(iteration + 1, :) ~= cckFrame.informationBits);
            totals(methodIndex) = totals(methodIndex) + numel(cckFrame.informationBits);
            frameErrors(methodIndex) = frameErrors(methodIndex) + any( ...
                informationHistory(iteration + 1, :) ~= cckFrame.informationBits);
        end

        for spreadingIndex = 1:3
            spreading = 2^spreadingIndex;
            [dsssErrors, dsssTotal] = dsss_rake_frame(spreading, cfg.frameWords * 4, ...
                cfg.snrList(snrIndex), cfg, baseSeed + 10 + spreadingIndex);
            methodIndex = 6 + spreadingIndex;
            errors(methodIndex) = errors(methodIndex) + dsssErrors;
            totals(methodIndex) = totals(methodIndex) + dsssTotal;
            frameErrors(methodIndex) = frameErrors(methodIndex) + (dsssErrors > 0);
        end
        frameTotal = frameTotal + 1;
    end
    errorCounts(:, snrIndex) = errors;
    bitTotals(:, snrIndex) = totals;
    frameErrorCounts(:, snrIndex) = frameErrors;
    frameTotals(:, snrIndex) = frameTotal;
end

ber = errorCounts ./ bitTotals;
displayBer = ber;
lowConfidencePositive = errorCounts > 0 & ...
    errorCounts < cfg.minimumErrorsForPlot;
displayBer(lowConfidencePositive) = nan;
displayBer(errorCounts == 0) = 0.5 ./ bitTotals(errorCounts == 0);

result.config = cfg;
result.methodLabels = methodLabels;
result.snrList = cfg.snrList;
result.ber = ber;
result.displayBer = displayBer;
result.errorCounts = errorCounts;
result.bitTotals = bitTotals;
result.frameErrorCounts = frameErrorCounts;
result.frameTotals = frameTotals;
result.fer = frameErrorCounts ./ frameTotals;
result.zeroErrorDisplayConvention = "0.5 / BitTotal";
result.receiverDefinitions = receiver_definitions();

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
result.figurePath = fullfile(cfg.outputDir, "fig5_26_uwa_dsss_cck_ber.png");
result.matPath = fullfile(cfg.outputDir, "fig5_26_uwa_dsss_cck_ber.mat");
result.csvPath = fullfile(cfg.outputDir, "fig5_26_uwa_dsss_cck_ber.csv");
write_figure(result);
write_table(result);
save(result.matPath, "result", "cfg");
end

function validate_config(cfg)
validateattributes(cfg.frameWords, {'numeric'}, {'scalar', 'integer', '>=', 4});
validateattributes(cfg.frameCount, {'numeric'}, {'scalar', 'integer', '>=', 1});
validateattributes(cfg.turboIterations, {'numeric'}, {'scalar', 'integer', '>=', 0});
validateattributes(cfg.trainingLength, {'numeric'}, {'scalar', 'integer', '>=', 16});
assert(numel(cfg.channelDelays) == numel(cfg.channelPowerDb) && ...
    numel(cfg.channelDelays) == numel(cfg.channelPhase), ...
    "SCFDE:InvalidUwaChannel", "Channel delay, power, and phase vectors must match.");
assert(numel(cfg.channelDelays) == numel(cfg.pathDopplerPerChip), ...
    "SCFDE:InvalidUwaDoppler", "Each path needs one Doppler rate.");
assert(cfg.channelDelays(1) == 0 && all(diff(cfg.channelDelays) > 0), ...
    "SCFDE:InvalidUwaDelay", "Channel delays must start at zero and be increasing.");
assert(cfg.pathTimeCorrelation > 0 && cfg.pathTimeCorrelation <= 1, ...
    "SCFDE:InvalidUwaCorrelation", "pathTimeCorrelation must be in (0, 1].");
assert(any(strcmpi(string(cfg.channelEstimateMode), ["ls", "perfect"])), ...
    "SCFDE:InvalidChannelEstimateMode", ...
    "channelEstimateMode must be ls or perfect.");
end

function ensure_ldpc_path(simulationDir)
if isempty(which("scfde_make_ldpc"))
    addpath(fullfile(simulationDir, "common"));
end
end

function frame = make_cck_frame(book, bitLabels, wordCount, ldpcCode, useInterleaver, seed)
rng(seed, "twister");
bitsPerWord = size(bitLabels, 2);
codedLength = wordCount * bitsPerWord;
informationLength = codedLength / 2;
assert(mod(codedLength, 2) == 0, "SCFDE:InvalidCckFrame", ...
    "The CCK coded bit length must be even.");
assert(informationLength == ldpcCode.K && codedLength == ldpcCode.N, ...
    "SCFDE:InvalidLdpcFrame", "The CCK frame length must match the LDPC code.");

frame.informationBits = randi([0, 1], 1, informationLength);
frame.codedBits = scfde_ldpc_encode(frame.informationBits, ldpcCode).';
if useInterleaver
    frame.interleaver = randperm(codedLength);
else
    frame.interleaver = 1:codedLength;
end
frame.transmittedBits = frame.codedBits(frame.interleaver);
wordBits = reshape(frame.transmittedBits, bitsPerWord, []).';
frame.wordIndices = 1 + wordBits * (2 .^ (0:bitsPerWord - 1)).';
frame.chips = reshape(book(frame.wordIndices, :).', [], 1);
end

function channel = propagate_uwa_frame(dataChips, energyPerBit, snrDb, cfg, seed)
rng(seed, "twister");
maximumDelay = cfg.channelDelays(end);
training = known_training(cfg.trainingLength);
guard = zeros(maximumDelay, 1);
transmitted = [training; guard; dataChips(:); zeros(maximumDelay, 1)];
pathSamples = time_varying_paths(numel(transmitted), cfg);
noiseless = apply_time_varying_paths(transmitted, pathSamples, cfg.channelDelays);
noiseVariance = energyPerBit * 10^(-snrDb / 10);
received = noiseless + sqrt(noiseVariance / 2) * ...
    (randn(size(noiseless)) + 1j * randn(size(noiseless)));

trainingRows = cfg.trainingLength + maximumDelay;
trainingMatrix = convolution_matrix(training, maximumDelay + 1);
lsEstimate = trainingMatrix \ received(1:trainingRows);
dataStart = cfg.trainingLength + maximumDelay + 1;
dataLength = numel(dataChips) + maximumDelay;
trueChannel = complex(zeros(maximumDelay + 1, 1));
trueChannel(cfg.channelDelays + 1) = pathSamples(dataStart, :);
if strcmpi(string(cfg.channelEstimateMode), "perfect")
    hHat = trueChannel;
else
    hHat = lsEstimate;
end
channel.receivedData = received(dataStart:dataStart + dataLength - 1);
channel.hHat = hHat(:);
channel.trueH = trueChannel;
channel.noiseVariance = noiseVariance;
channel.pathSamples = pathSamples;
channel.dataStart = dataStart;
end

function training = known_training(lengthTraining)
state = 1;
training = zeros(lengthTraining, 1);
for index = 1:lengthTraining
    training(index) = 1 - 2 * bitget(state, 1);
    feedback = bitxor(bitget(state, 7), bitget(state, 3));
    state = bitshift(state, 1);
    state = bitset(state, 1, feedback);
    state = bitand(state, 127);
    if state == 0
        state = 1;
    end
end
end

function matrix = convolution_matrix(signal, channelLength)
matrix = complex(zeros(numel(signal) + channelLength - 1, channelLength));
for tap = 1:channelLength
    matrix(tap:tap + numel(signal) - 1, tap) = signal;
end
end

function pathSamples = time_varying_paths(sampleCount, cfg)
pathCount = numel(cfg.channelDelays);
amplitudes = 10 .^ (cfg.channelPowerDb(:).' / 20);
amplitudes = amplitudes / norm(amplitudes);
nominal = amplitudes .* exp(1j * cfg.channelPhase(:).');
pathSamples = complex(zeros(sampleCount, pathCount));
state = nominal;
rho = cfg.pathTimeCorrelation;
innovationScale = sqrt(max(0, 1 - rho^2)) * cfg.pathFadingFraction;
for sample = 1:sampleCount
    if sample > 1
        innovation = (randn(1, pathCount) + 1j * randn(1, pathCount)) / sqrt(2);
        state = nominal + rho * (state - nominal) + ...
            innovationScale * amplitudes .* innovation;
    end
    pathSamples(sample, :) = state .* exp(1j * 2 * pi * ...
        cfg.pathDopplerPerChip(:).' * (sample - 1));
end
end

function received = apply_time_varying_paths(transmitted, pathSamples, delays)
received = complex(zeros(size(transmitted)));
for path = 1:numel(delays)
    delay = delays(path);
    indices = delay + 1:numel(transmitted);
    received(indices) = received(indices) + pathSamples(indices, path) .* ...
        transmitted(indices - delay);
end
end

function detected = cck_rake_detect(received, book, hHat)
wordLength = size(book, 2);
combined = rake_combine(received, hHat);
blockCount = floor(numel(combined) / wordLength);
blocks = reshape(combined(1:blockCount * wordLength), wordLength, []).';
detected = nearest_book(blocks, book);
end

function combined = rake_combine(received, hHat)
memory = numel(hHat) - 1;
matched = filter(conj(flipud(hHat)), 1, received(:));
first = memory + 1;
combined = matched(first:end) / max(sum(abs(hHat).^2), eps);
end

function informationBits = ldpc_hard_decode(codedBits, ldpcCode)
channelLlr = 8 * (1 - 2 * codedBits(:));
[decodedBits, ~, ~] = scfde_ldpc_decode(channelLlr, ldpcCode, 18);
informationBits = decodedBits(1:ldpcCode.K).';
end

function history = te_cck_detect(channel, frame, book, bitLabels, ldpcCode, cfg)
wordLength = size(book, 2);
bitsPerWord = size(bitLabels, 2);
dataLength = numel(frame.chips);
fftLength = 2^nextpow2(dataLength + numel(channel.hHat) - 1);
received = [channel.receivedData(:); zeros(fftLength - numel(channel.receivedData), 1)];
receivedSpectrum = fft(received);
channelSpectrum = fft([channel.hHat; zeros(fftLength - numel(channel.hHat), 1)]);
softChips = complex(zeros(dataLength, 1));
    priorLlr = zeros(1, numel(frame.transmittedBits));
history = false(cfg.turboIterations + 1, numel(frame.informationBits));

for iteration = 0:cfg.turboIterations
    reliability = min(0.985, mean(abs(softChips).^2));
    equalizer = conj(channelSpectrum) ./ (channel.noiseVariance + ...
        (1 - reliability) * abs(channelSpectrum).^2);
    equalizer = equalizer / max(mean(equalizer .* channelSpectrum), eps);
    feedback = equalizer .* channelSpectrum - 1;
    paddedSoft = [softChips; zeros(fftLength - dataLength, 1)];
    estimate = ifft(equalizer .* receivedSpectrum - feedback .* fft(paddedSoft));
    observations = reshape(estimate(1:dataLength), wordLength, []).';
    priorWords = reshape(priorLlr, bitsPerWord, []).';
    equalizedNoise = max(channel.noiseVariance * mean(abs(equalizer).^2) / ...
        cfg.teCckLlrScale, 1e-7);
    [softWords, posteriorLlr] = soft_cck_words(observations, book, bitLabels, ...
        equalizedNoise, priorWords);
    equalizerExtrinsicTx = reshape(posteriorLlr.', 1, []) - priorLlr;
    equalizerExtrinsic = deinterleave_llr_or_bits(equalizerExtrinsicTx, ...
        frame.interleaver);
    [decodedBits, decoderPosterior, ~] = scfde_ldpc_decode( ...
        equalizerExtrinsic(:), ldpcCode, cfg.ldpcDecoderIterations);
    history(iteration + 1, :) = decodedBits(1:ldpcCode.K).';
    if iteration < cfg.turboIterations
        decoderExtrinsic = decoderPosterior(:).' - equalizerExtrinsic;
        priorLlr = cfg.turboDamping * decoderExtrinsic(frame.interleaver);
        candidateSoft = reshape(softWords.', [], 1);
        softChips = 0.45 * softChips + 0.55 * candidateSoft;
    end
end

end

function output = deinterleave_llr_or_bits(input, interleaver)
output = zeros(size(input));
output(interleaver) = input;
end

function [softWords, posteriorLlr] = soft_cck_words(observations, book, ...
        bitLabels, noiseVariance, priorWords)
wordCount = size(observations, 1);
bitCount = size(bitLabels, 2);
distance = sum(abs(observations).^2, 2) + sum(abs(book).^2, 2).' - ...
    2 * real(observations * book');
metric = -distance / noiseVariance + 0.5 * priorWords * (1 - 2 * bitLabels).';
maximum = max(metric, [], 2);
probability = exp(metric - maximum);
probability = probability ./ sum(probability, 2);
softWords = probability * book;
posteriorLlr = zeros(wordCount, bitCount);
for bit = 1:bitCount
    posteriorLlr(:, bit) = row_log_sum_exp(metric(:, bitLabels(:, bit) == 0)) - ...
        row_log_sum_exp(metric(:, bitLabels(:, bit) == 1));
end
end

function [errors, total] = dsss_rake_frame(spreading, symbolCount, snrDb, cfg, seed)
rng(seed, "twister");
bits = randi([0, 1], symbolCount, 2);
symbols = ((1 - 2 * bits(:, 1)) + 1j * (1 - 2 * bits(:, 2))) / sqrt(2);
sequence = dsss_sequence(spreading);
chips = reshape(((symbols * sequence.') / sqrt(spreading)).', [], 1);
channel = propagate_uwa_frame(chips, 1 / 2, snrDb, cfg, seed + 1);
combined = rake_combine(channel.receivedData, channel.hHat);
usableLength = floor(numel(combined) / spreading) * spreading;
despread = reshape(combined(1:usableLength), spreading, []).' * ...
    conj(sequence) / sqrt(spreading);
equalized = dsss_symbol_lmmse(despread, channel.hHat, sequence, ...
    channel.noiseVariance);
detectedBits = [real(equalized) < 0, imag(equalized) < 0];
detectedBits = detectedBits(1:symbolCount, :);
errors = sum(detectedBits ~= bits, "all");
total = numel(bits);
end

function equalized = dsss_symbol_lmmse(observations, hHat, sequence, noiseVariance)
symbolCount = numel(observations);
response = dsss_effective_response(hHat, sequence);
kernel = complex(zeros(symbolCount, 1));
lags = response.lags;
for index = 1:numel(lags)
    kernel(mod(lags(index), symbolCount) + 1) = response.values(index);
end
frequencyResponse = fft(kernel);
combinedNoise = noiseVariance / max(sum(abs(hHat).^2), eps);
equalizer = conj(frequencyResponse) ./ (abs(frequencyResponse).^2 + combinedNoise);
equalized = ifft(equalizer .* fft(observations));
end

function response = dsss_effective_response(hHat, sequence)
spreading = numel(sequence);
memory = numel(hHat) - 1;
span = ceil(2 * memory / spreading) + 2;
symbolCount = 2 * span + 1;
center = span + 1;
reference = complex(zeros(symbolCount * spreading + 2 * memory, 1));
chipRange = (center - 1) * spreading + (1:spreading);
reference(chipRange) = sequence / sqrt(spreading);
received = filter(hHat, 1, reference);
combined = rake_combine([received; zeros(memory, 1)], hHat);
lags = -span:span;
values = complex(zeros(size(lags)));
for index = 1:numel(lags)
    block = center + lags(index);
    sampleRange = (block - 1) * spreading + (1:spreading);
    values(index) = combined(sampleRange).' * conj(sequence) / sqrt(spreading);
end
response.lags = lags;
response.values = values;
end

function sequence = dsss_sequence(spreading)
switch spreading
    case 2
        sequence = [1; -1];
    case 4
        sequence = [1; 1; -1; 1];
    case 8
        sequence = [1; 1; 1; -1; 1; -1; -1; -1];
    otherwise
        error("SCFDE:UnsupportedSpreading", ...
            "Figure 5-26 supports DSSS spreading lengths 2, 4, and 8.");
end
end

function detected = nearest_book(observations, book)
distance = sum(abs(observations).^2, 2) + sum(abs(book).^2, 2).' - ...
    2 * real(observations * book');
[~, detected] = min(distance, [], 2);
detected = detected.';
end

function value = log_sum_exp(values)
maximum = max(values);
value = maximum + log(sum(exp(values - maximum)));
end

function values = row_log_sum_exp(matrix)
maximum = max(matrix, [], 2);
values = maximum + log(sum(exp(matrix - maximum), 2));
end

function [book, bitLabels] = cck8_codebook()
book = complex(zeros(256, 8));
bitLabels = zeros(256, 8);
for index = 0:255
    rowBits = bitget(index, 1:8);
    bitLabels(index + 1, :) = rowBits;
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

function definitions = receiver_definitions()
definitions = struct();
definitions.channel = "Seven-path sparse UWA channel with path-wise Doppler and Gauss-Markov fading.";
definitions.channelEstimate = "Least-squares estimate from a 127-chip known training sequence.";
definitions.cckRake = "Matched-finger Rake plus CCK nearest-codeword decision and hard LDPC decoding.";
definitions.teCck = "Frequency-domain MMSE turbo equalizer, soft CCK word detector, and LDPC extrinsic-information exchange.";
definitions.dsss = "Matched-finger Rake, coherent despreading, and QPSK hard decision; residual equivalent-channel ISI is retained.";
end

function write_figure(result)
fig = figure("Color", "w", "Position", [120, 70, 980, 840], "Visible", "off");
ax = axes(fig, "Position", [0.15, 0.22, 0.75, 0.70]);
hold(ax, "on");
cckColor = [0.05, 0.05, 0.05];
dsssColor = [0.16, 0.33, 0.67];
styles = {"-o", "-<", "-*", "-s", "-+", "-d", "--o", "--s", "--*"};
for methodIndex = 1:numel(result.methodLabels)
    if methodIndex == 1
        color = [0.86, 0.18, 0.14];
    elseif methodIndex <= 6
        color = cckColor;
    else
        color = dsssColor;
    end
    markerFace = "none";
    if methodIndex == 4 || methodIndex == 8
        markerFace = color;
    end
    semilogy(ax, result.snrList, result.displayBer(methodIndex, :), styles{methodIndex}, ...
        "Color", color, "LineWidth", 1.45, "MarkerSize", 8, ...
        "MarkerFaceColor", markerFace, "DisplayName", result.methodLabels(methodIndex));
end
box(ax, "on");
grid(ax, "on");
ax.YMinorGrid = "on";
ax.GridLineStyle = "--";
ax.MinorGridLineStyle = "--";
ax.GridAlpha = 0.30;
ax.MinorGridAlpha = 0.20;
ax.FontName = "Microsoft YaHei";
ax.FontSize = 10.8;
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
legend(ax, "Location", "southwest", "FontSize", 9.4, "NumColumns", 1);
annotation(fig, "textbox", [0.14, 0.055, 0.75, 0.06], "String", ...
    "Fig 5-26: DSSS vs CCK BER over UWA channel", ...
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
