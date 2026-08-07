function results = reproduce_chapter2_sc_tde_paper(options)
%REPRODUCE_CHAPTER2_SC_TDE_PAPER Reproduce the simulations in Figs. 2-16 to 2-18.

if nargin < 1
    options = struct();
end
if isfield(options, "replotResultPath")
    resultPath = string(options.replotResultPath);
    assert(isfile(resultPath), "Saved Chapter 2 result was not found: %s", resultPath);
    stored = load(resultPath, "results");
    assert(isfield(stored, "results"), "The MAT file does not contain results: %s", resultPath);
    results = stored.results;
    results.paperReferenceBer = paper_figure_218_reference( ...
        results.config.snrDb, results.methodIndices);
    results.figurePaths = plot_paper_results(results);
    save(resultPath, "results");
    return;
end
defaults.snrDb = 0:2:14;
defaults.trainingSymbols = 1500;
defaults.dataSymbols = 4000;
defaults.trials = 3;
defaults.feedforwardTaps = 50;
defaults.feedbackTaps = 50;
defaults.ptrDecisionDelayOffset = 0;
defaults.mcDecisionDelayOffset = [];
defaults.rlsForgettingFactor = 0.9995;
defaults.rlsInitialInverseCorrelation = [];
defaults.normalizeDfeBranches = true;
defaults.scaleRlsInitializationByDimension = true;
defaults.rlsReferenceBranches = 8;
defaults.subarrayGroups = {1:2:8, 2:2:8};
defaults.ipnlmsStep = 0.35;
defaults.ipnlmsAlpha = 0.5;
defaults.equivalentChannelSnrDb = 15;
defaults.arrayNoiseMode = "per-branch";
defaults.residualDopplerSpanHz = 0;
defaults.methods = "all";
defaults.randomSeed = 20260725;
defaults.makePlot = true;
defaults.channelOptions = struct("source", "paper-figure");
defaults.outputDir = fullfile(fileparts(mfilename("fullpath")), ...
    "results", "sc_tde_paper_reproduction");
cfg = merge_options(defaults, options);

channelSource = "paper-figure";
if isfield(cfg.channelOptions, "source")
    channelSource = string(cfg.channelOptions.source);
end
if isempty(cfg.rlsInitialInverseCorrelation)
    if strcmpi(channelSource, "bellhop")
        cfg.rlsInitialInverseCorrelation = 0.003;
    else
        cfg.rlsInitialInverseCorrelation = 100;
    end
end
if ~isfield(options, "outputDir") && strcmpi(channelSource, "bellhop")
    cfg.outputDir = fullfile(fileparts(mfilename("fullpath")), ...
        "results", "sc_tde_bellhop_reproduction");
end

assert(cfg.trainingSymbols >= cfg.feedforwardTaps + cfg.feedbackTaps, ...
    "Training sequence is too short for the selected DFE lengths.");
assert(cfg.dataSymbols > 0 && cfg.trials > 0, ...
    "Data length and trial count must be positive.");
if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
cfg.channelOptions.outputDir = fullfile(cfg.outputDir, "bellhop");
rng(cfg.randomSeed, "twister");

channel = sc_tde_bellhop_array_channel(cfg.channelOptions);
cfg.symbolRate = channel.config.symbolRate;
trueChannels = channel.impulses;
assert(iscell(cfg.subarrayGroups) && numel(cfg.subarrayGroups) == 2, ...
    "subarrayGroups must contain exactly two receiver-index vectors.");
groups = {cfg.subarrayGroups{1}, cfg.subarrayGroups{2}, 1:8};
diagnosticTraining = qpsk_symbols(cfg.trainingSymbols);
diagnosticFrame = [diagnosticTraining, qpsk_symbols(cfg.dataSymbols), ...
    qpsk_symbols(cfg.trainingSymbols)];
diagnosticReceived = transmit_array(diagnosticFrame, trueChannels, ...
    cfg.equivalentChannelSnrDb, cfg);
diagnosticEstimatedChannels = estimate_array_ipnlms(diagnosticTraining, ...
    diagnosticReceived, size(trueChannels, 2), cfg);
equivalentChannels = passive_time_reversal_channels(trueChannels, ...
    diagnosticEstimatedChannels, groups);
availableMethodNames = ["PTR", "PTR-DFE", "McDFE", ...
    "Sub-PTR-McDFE", "Sub-PTR-BiMcDFE"];
methodIndices = select_method_indices(availableMethodNames, cfg.methods);
methodNames = availableMethodNames(methodIndices);
errorCounts = zeros(numel(methodNames), numel(cfg.snrDb));
bitCounts = zeros(size(errorCounts));

for snrIndex = 1:numel(cfg.snrDb)
    snrValue = cfg.snrDb(snrIndex);
    for trialIndex = 1:cfg.trials
        frontTraining = qpsk_symbols(cfg.trainingSymbols);
        tx = [frontTraining, qpsk_symbols(cfg.dataSymbols), ...
            qpsk_symbols(cfg.trainingSymbols)];
        received = transmit_array(tx, trueChannels, snrValue, cfg);
        estimatedChannels = estimate_array_ipnlms(frontTraining, ...
            received, size(trueChannels, 2), cfg);
        estimates = run_receiver_methods(received, estimatedChannels, tx, cfg);
        payload = cfg.trainingSymbols + (1:cfg.dataSymbols);
        for methodIndex = 1:numel(methodNames)
            estimateIndex = methodIndices(methodIndex);
            decisions = qpsk_slice(estimates{estimateIndex}(payload));
            errorCounts(methodIndex, snrIndex) = errorCounts(methodIndex, snrIndex) + ...
                sum(symbols_to_bits(decisions) ~= symbols_to_bits(tx(payload)));
            bitCounts(methodIndex, snrIndex) = bitCounts(methodIndex, snrIndex) + ...
                2 * cfg.dataSymbols;
        end
    end
    currentBer = errorCounts(:, snrIndex).' ./ bitCounts(:, snrIndex).';
    summaryText = methodNames + " " + compose("%.3g", currentBer);
    fprintf("SNR=%2g dB: %s\n", snrValue, join(summaryText, " | "));
end

results.config = cfg;
results.channel = channel;
results.trueChannels = trueChannels;
results.diagnosticEstimatedChannels = diagnosticEstimatedChannels;
results.equivalentChannels = equivalentChannels;
results.groups = groups;
results.methodNames = methodNames;
results.availableMethodNames = availableMethodNames;
results.methodIndices = methodIndices;
results.errorCounts = errorCounts;
results.bitCounts = bitCounts;
results.ber = errorCounts ./ bitCounts;
results.berSource = "Monte Carlo bit-error counting from the simulated receiver chain.";
results.paperReferenceBer = paper_figure_218_reference(cfg.snrDb, methodIndices);
results.paperReferenceSource = ...
    "Digitized approximation from the supplied Figure 2-18 image.";
% Relative Frobenius deviation of the simulated curves from the
% digitized reference (a value well below 1 with matching method
% ordering indicates a consistent reproduction).
results.frobeniusDeviation = ...
    norm(results.ber - results.paperReferenceBer, "fro") / ...
    max(norm(results.paperReferenceBer, "fro"), eps);
results.outputDir = cfg.outputDir;
results.resultPath = fullfile(cfg.outputDir, "chapter2_sc_tde_reproduction.mat");
results.figurePaths = strings(0, 1);
if cfg.makePlot
    results.figurePaths = plot_paper_results(results);
end
results.outputPath = results.resultPath;
save(results.resultPath, "results");
end

function selected = select_method_indices(available, requested)
requested = string(requested);
if isscalar(requested) && strcmpi(requested, "all")
    selected = 1:numel(available);
    return;
end
selected = zeros(1, numel(requested));
for index = 1:numel(requested)
    match = find(strcmpi(requested(index), available), 1);
    assert(~isempty(match), "SCFDE:UnknownMethod", ...
        "Unknown paper Chapter 2 method: %s. Available: %s", ...
        requested(index), strjoin(available, ", "));
    selected(index) = match;
end
assert(numel(unique(selected)) == numel(selected), ...
    "SCFDE:DuplicateMethod", "A paper Chapter 2 method was selected twice.");
end

function estimates = run_receiver_methods(received, channels, reference, cfg)
receiverCount = size(channels, 1);
allGroup = 1:receiverCount;
firstGroup = cfg.subarrayGroups{1};
secondGroup = cfg.subarrayGroups{2};

[fullPtrSignal, fullPtrChannel] = ptr_combine(received, channels, allGroup);
[firstPtrSignal, firstPtrChannel] = ptr_combine(received, channels, firstGroup);
[secondPtrSignal, secondPtrChannel] = ptr_combine(received, channels, secondGroup);
groupSignals = [firstPtrSignal; secondPtrSignal];
groupChannels = pad_rows({firstPtrChannel, secondPtrChannel});

estimates = cell(1, 5);
estimates{1} = sample_effective_channel(fullPtrSignal, fullPtrChannel, numel(reference));
estimates{2} = dfe_equalize(fullPtrSignal, fullPtrChannel, reference, cfg, ...
    cfg.ptrDecisionDelayOffset);
estimates{3} = dfe_equalize(received, channels, reference, cfg, ...
    cfg.mcDecisionDelayOffset);
estimates{4} = dfe_equalize(groupSignals, groupChannels, reference, cfg, ...
    cfg.ptrDecisionDelayOffset);

forward = estimates{4};
reverseSignals = fliplr(groupSignals);
reverseChannels = fliplr(groupChannels);
reverseReference = fliplr(reference);
backwardReversed = dfe_equalize(reverseSignals, reverseChannels, ...
    reverseReference, cfg, cfg.ptrDecisionDelayOffset);
backward = fliplr(backwardReversed);
estimates{5} = (forward + backward) / 2;
end

function estimated = estimate_array_ipnlms(training, received, channelLength, cfg)
receiverCount = size(received, 1);
estimated = complex(zeros(receiverCount, channelLength));
for receiverIndex = 1:receiverCount
    weights = complex(zeros(channelLength, 1));
    for symbolIndex = channelLength:cfg.trainingSymbols
        input = training(symbolIndex:-1:symbolIndex - channelLength + 1).';
        desired = received(receiverIndex, symbolIndex);
        estimate = weights' * input;
        error = desired - estimate;
        proportion = (1 - cfg.ipnlmsAlpha) / (2 * channelLength) + ...
            (1 + cfg.ipnlmsAlpha) * abs(weights) / ...
            (2 * sum(abs(weights)) + 1e-8);
        denominator = real(input' * (proportion .* input)) + 1e-8;
        weights = weights + cfg.ipnlmsStep * proportion .* input * conj(error) / denominator;
    end
    estimated(receiverIndex, :) = weights';
end
energy = sqrt(sum(abs(estimated).^2, "all"));
if energy > 0
    estimated = estimated / energy * sqrt(receiverCount);
end
end

function estimates = dfe_equalize(received, channels, reference, cfg, decisionDelayOffset)
if isvector(received)
    received = received(:).';
end
if isvector(channels)
    channels = channels(:).';
end
if cfg.normalizeDfeBranches
    branchNorms = sqrt(sum(abs(channels).^2, 2));
    branchNorms = max(branchNorms, sqrt(eps));
    received = received ./ branchNorms;
    channels = channels ./ branchNorms;
end
branchCount = size(channels, 1);
feedforwardLength = cfg.feedforwardTaps;
feedbackLength = cfg.feedbackTaps;
energyByDelay = sum(abs(channels).^2, 1);
[~, channelPeak] = max(energyByDelay);
if isempty(decisionDelayOffset)
    decisionDelayOffset = floor(feedforwardLength / 2);
end
decisionDelay = channelPeak - 1 + decisionDelayOffset;
coefficientCount = branchCount * feedforwardLength + feedbackLength;
firstTrainingSymbol = feedbackLength + 1;
estimates = complex(zeros(size(reference)));
decisions = complex(zeros(size(reference)));
decisions(1:cfg.trainingSymbols) = reference(1:cfg.trainingSymbols);
weights = complex(zeros(coefficientCount, 1));
inverseCorrelationScale = cfg.rlsInitialInverseCorrelation;
if cfg.scaleRlsInitializationByDimension
    referenceCoefficientCount = cfg.rlsReferenceBranches * feedforwardLength + ...
        feedbackLength;
    inverseCorrelationScale = inverseCorrelationScale * ...
        referenceCoefficientCount / coefficientCount;
end
inverseCorrelation = inverseCorrelationScale * eye(coefficientCount);
lambda = cfg.rlsForgettingFactor;
for symbolIndex = firstTrainingSymbol:numel(reference)
    if symbolIndex + decisionDelay > size(received, 2)
        break;
    end
    input = dfe_input(received, decisions, symbolIndex, decisionDelay, ...
        feedforwardLength, feedbackLength);
    estimates(symbolIndex) = weights' * input;
    if symbolIndex <= cfg.trainingSymbols
        desired = reference(symbolIndex);
    else
        desired = qpsk_slice(estimates(symbolIndex));
        decisions(symbolIndex) = desired;
    end
    correlationInput = inverseCorrelation * input;
    gain = correlationInput / (lambda + input' * correlationInput);
    error = desired - estimates(symbolIndex);
    weights = weights + gain * conj(error);
    inverseCorrelation = (inverseCorrelation - ...
        gain * correlationInput') / lambda;
end
end

function input = dfe_input(received, decisions, symbolIndex, decisionDelay, ...
    feedforwardLength, feedbackLength)
branchCount = size(received, 1);
input = complex(zeros(branchCount * feedforwardLength + feedbackLength, 1));
observationIndex = symbolIndex + decisionDelay;
for branchIndex = 1:branchCount
    range = (branchIndex - 1) * feedforwardLength + (1:feedforwardLength);
    sampleIndices = observationIndex:-1:observationIndex - feedforwardLength + 1;
    valid = sampleIndices >= 1 & sampleIndices <= size(received, 2);
    branchInput = complex(zeros(feedforwardLength, 1));
    branchInput(valid) = received(branchIndex, sampleIndices(valid)).';
    input(range) = branchInput;
end
input(branchCount * feedforwardLength + 1:end) = ...
    -decisions(symbolIndex - 1:-1:symbolIndex - feedbackLength).';
end

function received = transmit_array(input, channels, snrDb, cfg)
receiverCount = size(channels, 1);
receivedLength = numel(input) + size(channels, 2) - 1;
received = complex(zeros(receiverCount, receivedLength));
for receiverIndex = 1:receiverCount
    received(receiverIndex, :) = conv(input, channels(receiverIndex, :));
end
if cfg.residualDopplerSpanHz ~= 0
    branchDopplerHz = linspace(-cfg.residualDopplerSpanHz / 2, ...
        cfg.residualDopplerSpanHz / 2, receiverCount).';
    timeSeconds = (0:receivedLength - 1) / cfg.symbolRate;
    received = received .* exp(1j * 2 * pi * branchDopplerHz .* timeSeconds);
end
if strcmpi(cfg.arrayNoiseMode, "common")
    noisePowerByReceiver = repmat(mean(abs(received).^2, "all") / ...
        10^(snrDb / 10), receiverCount, 1);
elseif strcmpi(cfg.arrayNoiseMode, "per-branch")
    noisePowerByReceiver = mean(abs(received).^2, 2) / 10^(snrDb / 10);
else
    error("Unknown arrayNoiseMode: %s", cfg.arrayNoiseMode);
end
for receiverIndex = 1:receiverCount
    noisePower = noisePowerByReceiver(receiverIndex);
    noise = sqrt(noisePower / 2) * ...
        (randn(1, receivedLength) + 1j * randn(1, receivedLength));
    received(receiverIndex, :) = received(receiverIndex, :) + noise;
end
end

function [signal, effectiveChannel] = ptr_combine(received, channels, indices)
filterLength = size(channels, 2);
signalLength = size(received, 2) + filterLength - 1;
signal = complex(zeros(1, signalLength));
effectiveChannel = complex(zeros(1, 2 * filterLength - 1));
for receiverIndex = indices
    timeReverse = conj(fliplr(channels(receiverIndex, :)));
    signal = signal + conv(received(receiverIndex, :), timeReverse);
    effectiveChannel = effectiveChannel + conv(channels(receiverIndex, :), timeReverse);
end
end

function estimates = sample_effective_channel(signal, effectiveChannel, symbolCount)
[~, peakIndex] = max(abs(effectiveChannel));
mainTap = effectiveChannel(peakIndex);
indices = peakIndex + (0:symbolCount - 1);
estimates = complex(zeros(1, symbolCount));
valid = indices <= numel(signal);
estimates(valid) = signal(indices(valid)) / mainTap;
end

function channels = passive_time_reversal_channels(inputChannels, filterChannels, groups)
channelLength = size(inputChannels, 2);
channels = complex(zeros(numel(groups), 2 * channelLength - 1));
for groupIndex = 1:numel(groups)
    for receiverIndex = groups{groupIndex}
        channel = inputChannels(receiverIndex, :);
        timeReverseEstimate = conj(fliplr(filterChannels(receiverIndex, :)));
        channels(groupIndex, :) = channels(groupIndex, :) + ...
            conv(channel, timeReverseEstimate);
    end
end
peak = max(abs(channels(end, :)));
channels = channels / peak;
end

function symbols = qpsk_symbols(count)
bits = randi([0, 1], 2, count);
symbols = ((2 * bits(1, :) - 1) + 1j * (2 * bits(2, :) - 1)) / sqrt(2);
end

function decisions = qpsk_slice(values)
realPart = sign(real(values));
imagPart = sign(imag(values));
realPart(realPart == 0) = 1;
imagPart(imagPart == 0) = 1;
decisions = (realPart + 1j * imagPart) / sqrt(2);
end

function bits = symbols_to_bits(symbols)
bits = [real(symbols) > 0; imag(symbols) > 0];
bits = bits(:).';
end

function output = pad_rows(rows)
maxLength = max(cellfun(@numel, rows));
output = complex(zeros(numel(rows), maxLength));
for rowIndex = 1:numel(rows)
    output(rowIndex, 1:numel(rows{rowIndex})) = rows{rowIndex};
end
end

function figurePaths = plot_paper_results(results)
outputDir = results.outputDir;
figurePaths = [
    fullfile(outputDir, "fig2_16_bellhop_eight_channel.png")
    fullfile(outputDir, "fig2_17_passive_tr_equivalent_channel.png")
    fullfile(outputDir, "fig2_18_paper_digitized_reference.png")
    fullfile(outputDir, "fig2_18_channel_driven_simulation.png")
    ];
plot_bellhop_channels(results, figurePaths(1));
plot_equivalent_channels(results, figurePaths(2));
plot_ber(results.config.snrDb, results.paperReferenceBer, results.methodNames, ...
    figurePaths(3), "图 2-18  各种均衡方法的误码率曲线图（原图数字化参考）", []);
if isfield(results.channel, "source") && strcmpi(results.channel.source, "bellhop")
    simulationTitle = "图 2-18  Bellhop 复信道下的仿真 BER 曲线";
else
    simulationTitle = "图 2-18  基于图 2-16 数字化信道的仿真 BER 曲线";
end
plot_ber(results.config.snrDb, results.ber, results.methodNames, figurePaths(4), ...
    simulationTitle, 0.5 ./ results.bitCounts);
end

function plot_bellhop_channels(results, path)
fig = figure("Color", "w", "Position", [60, 60, 1400, 980], "Visible", "off");
tiledlayout(fig, 4, 2, "TileSpacing", "compact", "Padding", "compact");
isDigitized = isfield(results.channel, "source") && ...
    strcmpi(results.channel.source, "paper-figure");
for receiverIndex = 1:8
    nexttile;
    if isDigitized
        delays = results.channel.digitizedDelays{receiverIndex};
        amplitudes = results.channel.digitizedAmplitudes{receiverIndex};
        stem(delays, amplitudes, "o", "MarkerSize", 4, "LineWidth", 1.0);
        maximum = max(amplitudes);
        if maximum <= 0.6
            ylim([0, 0.6]);
        else
            ylim([0, 1.05]);
        end
        title(sprintf("(%c) 信道%d", char('a' + receiverIndex - 1), receiverIndex));
        xlabel("时间（码元间隔）"); ylabel("归一化幅度");
    else
        channel = results.trueChannels(receiverIndex, :);
        active = find(abs(channel) > max(abs(channel)) * 1e-4);
        stem(active - 1, abs(channel(active)) / max(abs(channel)), "o", ...
            "MarkerSize", 4, "LineWidth", 1.0);
        ylim([0, 1.05]);
        title(sprintf("(%c) 信道 %d：接收深度 %.1f m", ...
            char('a' + receiverIndex - 1), receiverIndex, ...
            results.channel.receiverDepths(receiverIndex)));
        xlabel("相对时延（码元间隔）"); ylabel("归一化幅度");
    end
    xlim([0, results.channel.config.maxDelaySymbols]); grid on;
end
apply_fonts(fig);
if isfield(results.channel, "source") && strcmpi(results.channel.source, "paper-figure")
    titleText = "图 2-16  按原图数字化的八阵元多径信道";
else
    titleText = "图 2-16  Bellhop 仿真得到的八阵元多径信道";
end
sgtitle(fig, titleText, ...
    "FontName", "Microsoft YaHei", "FontSize", 17, "FontWeight", "bold");
export_pair(fig, path);
end

function plot_equivalent_channels(results, path)
fig = figure("Color", "w", "Position", [80, 80, 1200, 760], "Visible", "off");
channels = results.equivalentChannels;
center = (size(channels, 2) + 1) / 2;
lags = (1:size(channels, 2)) - center;
plot(lags, abs(channels(1, :)), "LineWidth", 1.2);
hold on;
plot(lags, abs(channels(2, :)), "LineWidth", 1.2);
plot(lags, abs(channels(3, :)), "k-", "LineWidth", 1.5);
xlim([-100, 100]); ylim([0, 1.05]); grid on;
xlabel("相对时延（码元间隔）"); ylabel("归一化幅度");
title("图 2-17  被动时反处理后的等效信道");
legend("子阵列 1：[1,3,5,7]", "子阵列 2：[2,4,6,8]", ...
    "整个阵列：[1...8]", "Location", "northeast");
apply_fonts(fig);
export_pair(fig, path);
end

function referenceBer = paper_figure_218_reference(snrDb, methodIndices)
referenceSnrDb = 0:2:14;
referenceBer = [
    3.0e-1, 8.5e-2, 7.5e-2, 6.8e-2, 6.2e-2, 5.7e-2, 5.4e-2, 5.2e-2
    9.0e-2, 4.0e-2, 9.0e-3, 2.5e-3, 7.0e-4, 2.0e-4, 7.0e-5, 2.5e-5
    4.0e-2, 2.2e-2, 5.0e-3, 1.4e-3, 3.8e-4, 1.1e-4, 3.2e-5, 9.0e-6
    3.2e-2, 1.3e-2, 3.5e-3, 9.0e-4, 2.2e-4, 6.0e-5, 1.8e-5, 6.0e-6
    2.6e-2, 1.0e-2, 2.7e-3, 6.5e-4, 1.4e-4, 3.3e-5, 4.0e-6, 5.0e-7
    ];
snrDb = double(snrDb(:).');
interpolated = interp1(referenceSnrDb, log10(referenceBer).', snrDb, ...
    "linear", "extrap").';
referenceBer = 10 .^ interpolated(methodIndices, :);
end

function plot_ber(snrDb, ber, methodNames, path, titleText, minimumBer)
fig = figure("Color", "w", "Position", [80, 80, 1200, 780], "Visible", "off");
markers = ["o-", "*-", "x-", "^-", "d-"];
colors = [
    0.30, 0.30, 0.30
    0.05, 0.05, 0.05
    0.45, 0.45, 0.45
    0.20, 0.20, 0.20
    0.60, 0.60, 0.60
    ];
hold on;
for methodIndex = 1:numel(methodNames)
    values = ber(methodIndex, :);
    if ~isempty(minimumBer)
        values = max(values, minimumBer(methodIndex, :));
    end
    semilogy(snrDb, values, markers(methodIndex), "Color", colors(methodIndex, :), ...
        "LineWidth", 1.3, "MarkerSize", 7);
end
grid on;
set(gca, "YScale", "log", "YLim", [1e-7, 1], ...
    "YTick", 10 .^ (-7:0), ...
    "YTickLabel", compose("10^{%d}", -7:0), ...
    "TickLabelInterpreter", "tex", "YMinorGrid", "on");
xlabel("信噪比 SNR（dB）"); ylabel("误码率 BER");
title(titleText);
legend(methodNames, "Location", "southwest");
apply_fonts(fig);
export_pair(fig, path);
end

function apply_fonts(fig)
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei", "FontSize", 10);
end

function export_pair(fig, path)
exportgraphics(fig, path, "Resolution", 220);
[folder, name] = fileparts(path);
exportgraphics(fig, fullfile(folder, name + ".pdf"), "ContentType", "vector");
close(fig);
end

function merged = merge_options(defaults, overrides)
merged = defaults;
names = fieldnames(overrides);
for index = 1:numel(names)
    name = names{index};
    if isstruct(overrides.(name)) && isfield(merged, name) && isstruct(merged.(name))
        merged.(name) = merge_options(merged.(name), overrides.(name));
    else
        merged.(name) = overrides.(name);
    end
end
end
