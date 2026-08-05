function results = simulate_chapter4_figures410_411(options)
%SIMULATE_CHAPTER4_FIGURES410_411 FDE-FDDF BER with three estimators.

if nargin < 1
    options = struct();
end

rootDir = fileparts(mfilename("fullpath"));
addpath(fullfile(rootDir, "..", "common"));
cfg.fftSize = option_value(options, "fftSize", 512);
cfg.informationBits = option_value(options, "informationBits", 384);
cfg.channelLength = option_value(options, "channelLength", 133);
cfg.trainingSymbols = option_value(options, "trainingSymbols", 256);
cfg.symbolDurationMs = option_value(options, "symbolDurationMs", 0.25);
cfg.estimatorNames = ["IPNLMS", "OMP", "LS"];
cfg.reportedIterations = [0, 1, 3];
cfg.maximumIterations = max(cfg.reportedIterations);
cfg.qpskSnrDb = option_value(options, "qpskSnrDb", -5:2:5);
cfg.psk8SnrDb = option_value(options, "psk8SnrDb", 0:2:14);
cfg.maximumBits = option_value(options, "maximumBits", 2e5);
cfg.targetErrors = option_value(options, "targetErrors", 160);
cfg.ldpcIterations = option_value(options, "ldpcIterations", 1);
cfg.ompSparsity = option_value(options, "ompSparsity", 16);
cfg.ipnlmsIterations = option_value(options, "ipnlmsIterations", 2);
cfg.ipnlmsStep = option_value(options, "ipnlmsStep", 0.32);
cfg.ipnlmsAlpha = option_value(options, "ipnlmsAlpha", 0.5);
cfg.ipnlmsThresholdFactor = option_value(options, ...
    "ipnlmsThresholdFactor", 2.2);
cfg.ipnlmsRegularization = option_value(options, ...
    "ipnlmsRegularization", 1e-3);
cfg.channelNoiseFloor = option_value(options, "channelNoiseFloor", 0.20);
cfg.zeroIterationUsesDecoder = option_value(options, ...
    "zeroIterationUsesDecoder", false);
cfg.turboExtrinsicWeight = option_value(options, ...
    "turboExtrinsicWeight", 1.0);
cfg.decisionDirectedMinWeight = option_value(options, ...
    "decisionDirectedMinWeight", 0.05);
cfg.decisionDirectedMaxWeight = option_value(options, ...
    "decisionDirectedMaxWeight", 0.90);
cfg.randomSeed = option_value(options, "randomSeed", 20260731);
cfg.outputDir = string(option_value(options, "outputDir", ...
    fullfile(rootDir, "results")));

if isfield(options, "replotResultPath")
    stored = load(string(options.replotResultPath), "results");
    results = stored.results;
    cfg = results.config;
    combinedFigurePath = fullfile(cfg.outputDir, ...
        "fig4_10_4_11_channel_estimator_ber.png");
    plot_ber_figure(cfg.qpskSnrDb, results.qpskBer, ...
        results.qpskBitCounts, cfg, ...
        "图 4-10 三种信道估计下 QPSK 误码率曲线", ...
        results.qpskFigurePath);
    plot_ber_figure(cfg.psk8SnrDb, results.psk8Ber, ...
        results.psk8BitCounts, cfg, ...
        "图 4-11 三种信道估计下 8PSK 误码率曲线", ...
        results.psk8FigurePath);
    plot_combined_figure(results.qpskBer, results.qpskBitCounts, ...
        results.psk8Ber, results.psk8BitCounts, cfg, combinedFigurePath);
    results.combinedFigurePath = combinedFigurePath;
    save(string(options.replotResultPath), "results", "-v7.3");
    return;
end

assert(mod(2 * cfg.informationBits, 2) == 0, ...
    "The LDPC codeword must fit QPSK symbols.");
assert(mod(2 * cfg.informationBits, 3) == 0, ...
    "The LDPC codeword must fit 8PSK symbols.");
assert(cfg.channelLength <= cfg.fftSize, ...
    "The channel estimate cannot exceed the DFT block.");
assert(cfg.trainingSymbols >= cfg.channelLength, ...
    "The training UW must cover the channel impulse response.");

channelSource = load_channel_source(rootDir);
ldpc = scfde_make_ldpc(cfg.informationBits);
rng(cfg.randomSeed, "twister");

fprintf("Running Figure 4-10 QPSK simulation...\n");
[qpskErrors, qpskBits, qpskBer] = simulate_modulation( ...
    cfg, channelSource, ldpc, 4, cfg.qpskSnrDb);
fprintf("Running Figure 4-11 8PSK simulation...\n");
[psk8Errors, psk8Bits, psk8Ber] = simulate_modulation( ...
    cfg, channelSource, ldpc, 8, cfg.psk8SnrDb);

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
qpskFigurePath = fullfile(cfg.outputDir, ...
    "fig4_10_qpsk_channel_estimator_ber.png");
psk8FigurePath = fullfile(cfg.outputDir, ...
    "fig4_11_8psk_channel_estimator_ber.png");
combinedFigurePath = fullfile(cfg.outputDir, ...
    "fig4_10_4_11_channel_estimator_ber.png");
plot_ber_figure(cfg.qpskSnrDb, qpskBer, qpskBits, cfg, ...
    "图 4-10 三种信道估计下 QPSK 误码率曲线", qpskFigurePath);
plot_ber_figure(cfg.psk8SnrDb, psk8Ber, psk8Bits, cfg, ...
    "图 4-11 三种信道估计下 8PSK 误码率曲线", psk8FigurePath);
plot_combined_figure(qpskBer, qpskBits, psk8Ber, psk8Bits, ...
    cfg, combinedFigurePath);

resultPath = fullfile(cfg.outputDir, ...
    "fig4_10_4_11_fde_fddf_ber_simulation.mat");
results.config = cfg;
results.qpskErrorCounts = qpskErrors;
results.qpskBitCounts = qpskBits;
results.qpskBer = qpskBer;
results.psk8ErrorCounts = psk8Errors;
results.psk8BitCounts = psk8Bits;
results.psk8Ber = psk8Ber;
results.channelSourcePath = channelSource.resultPath;
results.qpskFigurePath = qpskFigurePath;
results.psk8FigurePath = psk8FigurePath;
results.combinedFigurePath = combinedFigurePath;
results.resultPath = resultPath;
results.berSource = "Integer bit-error counting through the simulated FDE-FDDF chain.";
results.iterationDefinition = [ ...
    "One outer iteration equals one LDPC message-passing sweep, ", ...
    "one APP soft-symbol feedback update, and one channel re-estimation."];
save(resultPath, "results", "-v7.3");

assert(all(qpskBer(:) == qpskErrors(:) ./ qpskBits(:)), ...
    "QPSK BER is inconsistent with integer error counts.");
assert(all(psk8Ber(:) == psk8Errors(:) ./ psk8Bits(:)), ...
    "8PSK BER is inconsistent with integer error counts.");
fprintf("Figures 4-10 and 4-11 written to: %s\n", cfg.outputDir);
end

function source = load_channel_source(rootDir)
resultPath = fullfile(rootDir, "results", ...
    "fig4_9_time_varying_channel_impulse_response.mat");
if ~exist(resultPath, "file")
    generated = simulate_chapter4_figure49(struct( ...
        "outputDir", fullfile(rootDir, "results")));
    source = generated;
else
    stored = load(resultPath, "results");
    source = stored.results;
end
source.resultPath = resultPath;
end

function [errorCounts, bitCounts, ber] = simulate_modulation( ...
        cfg, source, ldpc, modulationOrder, snrList)
methodCount = numel(cfg.estimatorNames);
iterationCount = numel(cfg.reportedIterations);
errorCounts = zeros(methodCount, iterationCount, numel(snrList));
bitCounts = zeros(size(errorCounts));
constellation = psk_constellation(modulationOrder);
bitsPerSymbol = log2(modulationOrder);
dataSymbols = ldpc.N / bitsPerSymbol;
guardSymbols = cfg.fftSize - dataSymbols;
guardStream = RandStream("mt19937ar", ...
    "Seed", 4100 + modulationOrder);
guardBits = randi(guardStream, [0, 1], ...
    guardSymbols * bitsPerSymbol, 1);
guard = map_psk(guardBits, constellation);
interleaverStream = RandStream("mt19937ar", ...
    "Seed", 4200 + modulationOrder);
permutation = randperm(interleaverStream, ldpc.N).';
inversePermutation = zeros(ldpc.N, 1);
inversePermutation(permutation) = (1:ldpc.N).';
training = zadoff_chu(cfg.trainingSymbols, 1);

for snrIndex = 1:numel(snrList)
    errors = zeros(methodCount, iterationCount);
    totalBits = 0;
    frameIndex = 0;
    while totalBits < cfg.maximumBits && min(errors(:)) < cfg.targetErrors
        frameIndex = frameIndex + 1;
        timeIndex = 1 + mod(11 * frameIndex + 7 * snrIndex, ...
            numel(source.config.timeSec));
        channels = channel_snapshot(source, timeIndex, cfg);
        infoBits = randi([0, 1], ldpc.K, 1);
        codeword = scfde_ldpc_encode(infoBits, ldpc);
        data = map_psk(codeword(permutation), constellation);
        transmitted = [data; guard];
        [receivedData, receivedTraining, noiseVariance] = ...
            transmit_frame(transmitted, training, channels, ...
            snrList(snrIndex));

        for methodIndex = 1:methodCount
            decoderPriorLlr = zeros(ldpc.N, 1);
            estimatedChannels = estimate_channel_bank(receivedTraining, ...
                training, cfg, cfg.estimatorNames(methodIndex));
            [decodedInfo, decodedCodeword, posteriorLlr, rawCodeword, ...
                channelLlr] = ...
                equalize_decode(receivedData, estimatedChannels, ...
                noiseVariance, constellation, dataSymbols, ldpc, cfg, ...
                complex(zeros(cfg.fftSize, 1)), 0, ...
                inversePermutation, zeros(ldpc.N, 1));
            if cfg.zeroIterationUsesDecoder
                baselineInfo = decodedInfo;
            else
                baselineInfo = rawCodeword(1:ldpc.K);
            end
            errors(methodIndex, 1) = errors(methodIndex, 1) + ...
                sum(baselineInfo ~= infoBits);

            reportIndex = 2;
            for iteration = 1:cfg.maximumIterations
                decoderExtrinsic = cfg.turboExtrinsicWeight * ...
                    max(min(posteriorLlr - channelLlr - decoderPriorLlr, ...
                    20), -20);
                decoderPosterior = max(min(posteriorLlr, 20), -20);
                feedbackData = posterior_psk_mean( ...
                    decoderPosterior(permutation), constellation);
                reliability = min(0.98, ...
                    sqrt(mean(abs(feedbackData).^2)));
                if any(mod(ldpc.H * decodedCodeword, 2))
                    reliability = min(reliability, 0.90);
                end
                feedback = [feedbackData; guard];
                decisionDirected = estimate_channel_bank(receivedData, ...
                    feedback, cfg, cfg.estimatorNames(methodIndex), ...
                    estimatedChannels);
                updateWeight = min(cfg.decisionDirectedMaxWeight, ...
                    max(cfg.decisionDirectedMinWeight, reliability^2));
                candidateChannels = (1 - updateWeight) * ...
                    estimatedChannels + updateWeight * decisionDirected;
                [candidateInfo, candidateCodeword, candidateLlr, ~, ...
                    candidateChannelLlr] = ...
                    equalize_decode(receivedData, candidateChannels, ...
                    noiseVariance, constellation, dataSymbols, ldpc, cfg, ...
                    fft(feedback), reliability, inversePermutation, ...
                    decoderExtrinsic);
                estimatedChannels = candidateChannels;
                decodedInfo = candidateInfo;
                decodedCodeword = candidateCodeword;
                posteriorLlr = candidateLlr;
                channelLlr = candidateChannelLlr;
                decoderPriorLlr = decoderExtrinsic;
                if reportIndex <= iterationCount && ...
                        iteration == cfg.reportedIterations(reportIndex)
                    errors(methodIndex, reportIndex) = ...
                        errors(methodIndex, reportIndex) + ...
                        sum(decodedInfo ~= infoBits);
                    reportIndex = reportIndex + 1;
                end
            end
        end
        totalBits = totalBits + ldpc.K;
    end
    errorCounts(:, :, snrIndex) = errors;
    bitCounts(:, :, snrIndex) = totalBits;
    fprintf("  %s SNR %g dB: %d bits\n", ...
        modulation_name(modulationOrder), snrList(snrIndex), totalBits);
end
ber = errorCounts ./ bitCounts;
end

function channels = channel_snapshot(source, timeIndex, cfg)
delaySamplesMs = (0:cfg.channelLength - 1) * cfg.symbolDurationMs;
branchCount = size(source.complexResponse, 3);
channels = complex(zeros(branchCount, cfg.channelLength));
for branchIndex = 1:branchCount
    impulse = interp1(source.config.delayMs, ...
        source.complexResponse(timeIndex, :, branchIndex), ...
        delaySamplesMs, "linear", 0);
    magnitude = abs(impulse);
    impulse = impulse .* max(magnitude - cfg.channelNoiseFloor, 0) ./ ...
        max(magnitude, eps);
    impulse = impulse .* tukey_window(cfg.channelLength, 0.08).';
    channels(branchIndex, :) = impulse / max(norm(impulse), eps);
end
end

function [receivedData, receivedTraining, noiseVariance] = ...
        transmit_frame(transmitted, training, channels, snrDb)
branchCount = size(channels, 1);
blockLength = numel(transmitted);
transmittedSpectrum = fft(transmitted);
trainingSpectrum = fft(training);
cleanData = complex(zeros(branchCount, blockLength));
cleanTraining = complex(zeros(branchCount, numel(training)));
for branchIndex = 1:branchCount
    channelSpectrum = fft(channels(branchIndex, :), blockLength);
    cleanData(branchIndex, :) = ifft(channelSpectrum .* ...
        transmittedSpectrum.').';
    trainingChannelSpectrum = fft(channels(branchIndex, :), ...
        numel(training));
    cleanTraining(branchIndex, :) = ifft(trainingChannelSpectrum .* ...
        trainingSpectrum.').';
end
signalPower = mean(abs(cleanData).^2, "all");
noiseVariance = signalPower * 10^(-snrDb / 10);
receivedData = cleanData + sqrt(noiseVariance / 2) * ...
    (randn(size(cleanData)) + 1j * randn(size(cleanData)));
receivedTraining = cleanTraining + sqrt(noiseVariance / 2) * ...
    (randn(size(cleanTraining)) + 1j * randn(size(cleanTraining)));
end

function estimated = estimate_channel_bank(receivedTraining, ...
        training, cfg, method, initialChannels)
if nargin < 5
    initialChannels = [];
end
branchCount = size(receivedTraining, 1);
estimated = complex(zeros(branchCount, cfg.fftSize));
regression = circular_training_matrix(training, cfg.channelLength);
gramScale = real(trace(regression' * regression)) / cfg.channelLength;
for branchIndex = 1:branchCount
    observation = receivedTraining(branchIndex, :).';
    switch method
        case "LS"
            regularization = 1e-3 * gramScale;
            impulse = (regression' * regression + ...
                regularization * eye(cfg.channelLength)) \ ...
                (regression' * observation);
        case "OMP"
            impulse = omp_channel_estimate(regression, observation, ...
                cfg.ompSparsity);
        case "IPNLMS"
            initialImpulse = complex(zeros(cfg.channelLength, 1));
            if ~isempty(initialChannels)
                previousImpulse = ifft(initialChannels(branchIndex, :));
                initialImpulse = previousImpulse(1:cfg.channelLength).';
            end
            impulse = ipnlms_channel_estimate( ...
                regression, observation, cfg, initialImpulse);
        otherwise
            error("Figure410:UnknownEstimator", ...
                "Unknown channel estimator: %s", method);
    end
    estimated(branchIndex, :) = fft(impulse, cfg.fftSize).';
end
end

function regression = circular_training_matrix(training, channelLength)
training = training(:);
regression = complex(zeros(numel(training), channelLength));
for tapIndex = 1:channelLength
    regression(:, tapIndex) = circshift(training, tapIndex - 1);
end
end

function estimate = omp_channel_estimate(regression, observation, sparsity)
estimate = complex(zeros(size(regression, 2), 1));
residual = observation;
maximumIterations = min(sparsity, size(regression, 2));
support = zeros(maximumIterations, 1);
supportCount = 0;
for iterationIndex = 1:maximumIterations
    correlation = abs(regression' * residual);
    correlation(support(1:supportCount)) = 0;
    [peak, selected] = max(correlation);
    if peak <= eps
        break;
    end
    supportCount = supportCount + 1;
    support(supportCount) = selected;
    activeSupport = support(1:supportCount);
    estimate(activeSupport) = regression(:, activeSupport) \ observation;
    residual = observation - regression(:, activeSupport) * ...
        estimate(activeSupport);
end
end

function estimate = ipnlms_channel_estimate( ...
        regression, observation, cfg, initialEstimate)
estimate = initialEstimate;
regularization = cfg.ipnlmsRegularization * ...
    mean(abs(observation).^2);
for passIndex = 1:cfg.ipnlmsIterations
    for sampleIndex = 1:size(regression, 1)
        input = regression(sampleIndex, :).';
        error = observation(sampleIndex) - input.' * estimate;
        proportion = (1 - cfg.ipnlmsAlpha) / ...
            (2 * cfg.channelLength) + ...
            (1 + cfg.ipnlmsAlpha) * abs(estimate) / ...
            (2 * sum(abs(estimate)) + eps);
        normalization = sum(proportion .* abs(input).^2) + ...
            regularization;
        estimate = estimate + cfg.ipnlmsStep * proportion .* ...
            conj(input) * error / max(normalization, eps);
    end
end
adaptiveFloor = cfg.ipnlmsThresholdFactor * median(abs(estimate));
estimate(abs(estimate) < adaptiveFloor) = 0;
end

function [infoBits, codewordBits, posteriorLlr, rawCodeword, channelLlr] = ...
        equalize_decode( ...
        received, channels, noiseVariance, constellation, dataSymbols, ...
        ldpc, cfg, feedbackSpectrum, reliability, inversePermutation, ...
        priorLlr)
receivedSpectrum = fft(received, [], 2);
channelPower = sum(abs(channels).^2, 1);
D = (noiseVariance + channelPower) - reliability * channelPower;
lambda = noiseVariance * sum(1 ./ max(D, eps)) / ...
    max(sum((noiseVariance + channelPower) ./ max(D, eps)), eps);
feedbackFilter = (lambda * (noiseVariance + channelPower) - noiseVariance) ...
    ./ max(D, eps);
feedforward = conj(channels) .* (1 + feedbackFilter) ./ ...
    (noiseVariance + channelPower);
estimateSpectrum = sum(feedforward .* receivedSpectrum, 1).' - ...
    feedbackFilter.' .* feedbackSpectrum;
estimate = ifft(estimateSpectrum);
effectiveNoise = noiseVariance * mean(sum(abs(feedforward).^2, 1));
effectiveNoise = effectiveNoise + (1 - reliability) * ...
    mean(abs(feedbackFilter).^2);
interleavedLlr = psk_llr(estimate(1:dataSymbols), constellation, ...
    max(effectiveNoise, 1e-4));
channelLlr = interleavedLlr(inversePermutation);
rawCodeword = channelLlr < 0;
[codewordBits, posteriorLlr] = scfde_ldpc_decode( ...
    channelLlr + priorLlr, ldpc, cfg.ldpcIterations);
infoBits = codewordBits(1:ldpc.K);
end

function definition = psk_constellation(modulationOrder)
bitsPerSymbol = log2(modulationOrder);
phaseIndex = (0:modulationOrder - 1).';
grayLabel = bitxor(phaseIndex, floor(phaseIndex / 2));
labels = zeros(modulationOrder, bitsPerSymbol);
for bitIndex = 1:bitsPerSymbol
    labels(:, bitIndex) = bitget(grayLabel, ...
        bitsPerSymbol - bitIndex + 1);
end
definition.points = exp(1j * 2 * pi * phaseIndex / modulationOrder);
definition.labels = labels;
definition.bitsPerSymbol = bitsPerSymbol;
definition.order = modulationOrder;
end

function symbols = map_psk(bits, definition)
groups = reshape(bits, definition.bitsPerSymbol, []).';
weights = 2.^(definition.bitsPerSymbol - 1:-1:0).';
labels = groups * weights;
grayValues = definition.labels * weights;
inverseMap = zeros(definition.order, 1);
for phaseIndex = 1:definition.order
    inverseMap(grayValues(phaseIndex) + 1) = phaseIndex;
end
symbols = definition.points(inverseMap(labels + 1));
end

function symbols = posterior_psk_mean(bitLlr, definition)
symbolBitLlr = reshape(bitLlr, definition.bitsPerSymbol, []).';
labelSigns = 1 - 2 * definition.labels;
logProbability = 0.5 * symbolBitLlr * labelSigns.';
logProbability = logProbability - max(logProbability, [], 2);
probability = exp(logProbability);
probability = probability ./ sum(probability, 2);
symbols = probability * definition.points;
end

function llr = psk_llr(symbols, definition, noiseVariance)
distance = abs(symbols(:) - definition.points.').^2;
symbolCount = numel(symbols);
bitLlr = zeros(symbolCount, definition.bitsPerSymbol);
for bitIndex = 1:definition.bitsPerSymbol
    distanceZero = min(distance(:, definition.labels(:, bitIndex) == 0), ...
        [], 2);
    distanceOne = min(distance(:, definition.labels(:, bitIndex) == 1), ...
        [], 2);
    bitLlr(:, bitIndex) = (distanceOne - distanceZero) / noiseVariance;
end
llr = reshape(bitLlr.', [], 1);
end

function sequence = zadoff_chu(lengthValue, root)
index = (0:lengthValue - 1).';
sequence = exp(-1j * pi * root * index.^2 / lengthValue);
end

function window = tukey_window(lengthValue, fraction)
window = ones(lengthValue, 1);
edge = floor(fraction * (lengthValue - 1) / 2);
if edge > 0
    phase = (0:edge - 1).' / edge;
    taper = 0.5 * (1 - cos(pi * phase));
    window(1:edge) = taper;
    window(end - edge + 1:end) = flipud(taper);
end
end

function plot_ber_figure(snrList, ber, bitCounts, cfg, titleText, path)
fig = figure("Color", "w", "Position", [100, 80, 900, 650]);
axesHandle = axes(fig);
draw_ber_axes(axesHandle, snrList, ber, bitCounts, cfg, ...
    titleText, "southwest");
exportgraphics(fig, path, "Resolution", 200);
close(fig);
end

function plot_combined_figure(qpskBer, qpskBits, psk8Ber, psk8Bits, ...
        cfg, path)
fig = figure("Color", "w", "Position", [100, 40, 900, 1120]);
layout = tiledlayout(fig, 2, 1, "TileSpacing", "compact", ...
    "Padding", "compact");
qpskAxes = nexttile(layout);
draw_ber_axes(qpskAxes, cfg.qpskSnrDb, qpskBer, qpskBits, cfg, ...
    "图 4-10 三种信道估计下 QPSK 误码率曲线", "southwest");
psk8Axes = nexttile(layout);
draw_ber_axes(psk8Axes, cfg.psk8SnrDb, psk8Ber, psk8Bits, cfg, ...
    "图 4-11 三种信道估计下 8PSK 误码率曲线", "northeast");
exportgraphics(fig, path, "Resolution", 200);
close(fig);
end

function draw_ber_axes(axesHandle, snrList, ber, bitCounts, cfg, ...
        titleText, legendLocation)
styles = ["-", "--", "-."];
markers = ["x", "o", "*"];
colors = [0.8500, 0.1200, 0.1000; ...
    0.0500, 0.3000, 0.7000; 0.1000, 0.1000, 0.1000];
hold(axesHandle, "on");
legendNames = strings(0, 1);
for methodIndex = 1:numel(cfg.estimatorNames)
    for iterationIndex = 1:numel(cfg.reportedIterations)
        plotFloor = 0.5 ./ squeeze(bitCounts(methodIndex, ...
            iterationIndex, :));
        values = max(squeeze(ber(methodIndex, iterationIndex, :)), ...
            plotFloor);
        semilogy(axesHandle, snrList, values, ...
            "LineStyle", styles(iterationIndex), ...
            "Marker", markers(iterationIndex), ...
            "Color", colors(methodIndex, :), ...
            "LineWidth", 1.25, "MarkerSize", 6);
        legendNames(end + 1) = compose("FDE-FDDF %s %d次迭代", ...
            cfg.estimatorNames(methodIndex), ...
            cfg.reportedIterations(iterationIndex)); %#ok<AGROW>
    end
end
grid(axesHandle, "on");
if min(snrList) == max(snrList)
    xlim(axesHandle, [snrList(1) - 1, snrList(1) + 1]);
else
    xlim(axesHandle, [min(snrList), max(snrList)]);
end
ylim(axesHandle, [1e-7, 1]);
xlabel(axesHandle, "信噪比 SNR（dB）");
ylabel(axesHandle, "误码率 BER");
title(axesHandle, titleText);
legend(axesHandle, legendNames, "Location", legendLocation, ...
    "FontSize", 9);
set(axesHandle, "FontName", "Microsoft YaHei", "FontSize", 11, ...
    "YScale", "log");
end

function name = modulation_name(modulationOrder)
if modulationOrder == 4
    name = "QPSK";
else
    name = "8PSK";
end
end

function value = option_value(options, name, defaultValue)
if isfield(options, name)
    value = options.(name);
else
    value = defaultValue;
end
end
