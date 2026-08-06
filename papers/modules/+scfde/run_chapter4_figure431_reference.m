function results = run_chapter4_figure431_reference(options, simulationDir)
%RUN_CHAPTER4_FIGURE431_REFERENCE Paper-aligned simulation of Figure 4-31.

if nargin < 1
    options = struct();
end
if nargin < 2 || isempty(simulationDir)
    simulationDir = fileparts(fileparts(mfilename("fullpath")));
end

defaults.snrDb = -5:1:10;
defaults.outerIterations = 3;
defaults.innerIterations = 2;
defaults.frameCount = 8;
defaults.blocksPerFrame = 9;
defaults.trainingSymbols = 256;
defaults.dataSymbols = 1024;
defaults.subblockLength = 32;
defaults.feedforwardTaps = 64;
defaults.feedbackTaps = 20;
defaults.forwardStep = 0.20;
defaults.feedbackStep = 0.01;
defaults.timeStep = 0.50;
defaults.turboDamping = 0.35;
defaults.regularization = 1e-3;
defaults.trainingRegularization = 0;
defaults.channelEstimateMode = "ls";
defaults.fdTrainingIterations = 2;
defaults.fdTrainingStepScale = 0.25;
defaults.fdUpdateStepScale = 1;
defaults.channelSource = "bellhop";
defaults.bellhopRoot = "D:\MATLAB\atWin10_2020_11_4\atWin10_2020_11_4";
defaults.waterDepth = 50;
defaults.sourceDepth = 30;
defaults.receiverDepths = [24, 28];
defaults.rangeKm = 3;
defaults.carrierHz = 10000;
defaults.symbolRate = 5000;
defaults.maxDopplerHz = 0.50;
defaults.noisePowerFactor = 1;
defaults.maxDelaySymbols = 64;
defaults.paperRayDelays = [0, 14, 27, 40];
defaults.paperRayGains = [1.00, 0.64, 0.48, 0.36];
defaults.outputDir = fullfile(simulationDir, "chapter4_simulation", "results");
defaults.randomSeed = 20260731;
defaults.berMetric = "information";
defaults.figureBaseName = "fig4_31_ted_teq_uncoded_ber";
cfg = merge_options(defaults, options);
cfg.blockLength = cfg.trainingSymbols + cfg.dataSymbols;
assert(cfg.trainingSymbols == 256 && cfg.dataSymbols == 1024, ...
    "Figure431:InvalidBlock", ...
    "The reference configuration requires 256 training and 1024 data symbols.");
assert(mod(cfg.dataSymbols, cfg.subblockLength) == 0, ...
    "Figure431:InvalidSubblock", "Data symbols must be divisible by subblock length.");

if ~exist(cfg.outputDir, "dir")
    mkdir(cfg.outputDir);
end
rng(cfg.randomSeed, "twister");
channel = build_channel(cfg);

methodNames = ["TDDA-TEQ", "FDCE-TEQ", "FDDA-TEQ"];
methodCount = numel(methodNames);
ber = zeros(methodCount, cfg.outerIterations, numel(cfg.snrDb));
errorCounts = zeros(size(ber));
allCodedErrorCounts = zeros(size(ber));
bitCounts = zeros(1, numel(cfg.snrDb));
for snrIndex = 1:numel(cfg.snrDb)
    errors = zeros(methodCount, cfg.outerIterations);
    codedErrors = zeros(methodCount, cfg.outerIterations);
    totalBits = 0;
    for frameIndex = 1:frame_count_at(cfg.frameCount, snrIndex)
        for blockIndex = 1:cfg.blocksPerFrame
            block = make_block(cfg, channel, cfg.snrDb(snrIndex));
            if strcmpi(string(cfg.berMetric), "coded")
                errors = errors + block.errors;
                totalBits = totalBits + cfg.dataSymbols;
            else
                errors = errors + block.codedErrors;
                totalBits = totalBits + 2 * cfg.dataSymbols;
            end
            codedErrors = codedErrors + block.codedErrors;
        end
    end
    errorCounts(:, :, snrIndex) = errors;
    allCodedErrorCounts(:, :, snrIndex) = codedErrors;
    ber(:, :, snrIndex) = errors / totalBits;
    bitCounts(snrIndex) = totalBits;
    fprintf("Figure 4-31: SNR=%g dB, bits=%d\n", cfg.snrDb(snrIndex), totalBits);
end

figurePath = fullfile(cfg.outputDir, cfg.figureBaseName + ".png");
resultPath = fullfile(cfg.outputDir, cfg.figureBaseName + ".mat");
plot_reference_figure(cfg, methodNames, ber, figurePath);
results.config = cfg;
results.channel = channel;
results.methodNames = methodNames;
results.snrDb = cfg.snrDb;
results.ber = ber;
results.errorCounts = errorCounts;
results.bitCounts = bitCounts;
results.figurePath = figurePath;
results.resultPath = resultPath;
if strcmpi(string(cfg.berMetric), "coded")
    results.berDefinition = "Information-bit BER after rate-1/2 convolutional Log-MAP decoding";
else
    results.berDefinition = "Coded-bit BER before convolutional decoding";
end
results.codedErrorCounts = allCodedErrorCounts;
results.referenceParameters = struct( ...
    "modulation", "QPSK", ...
    "code", "Rate-1/2 convolutional code, G=(7,5)", ...
    "frame", "9 blocks, each 256 training plus 1024 information QPSK symbols", ...
    "subblockLength", cfg.subblockLength, ...
    "outerIterations", cfg.outerIterations, ...
    "innerIterations", cfg.innerIterations, ...
    "forwardStep", cfg.forwardStep, ...
    "feedbackStep", cfg.feedbackStep);
save(resultPath, "results", "-v7.3");
countArray = repmat(reshape(bitCounts, 1, 1, []), methodCount, cfg.outerIterations, 1);
assert(all(abs(ber(:) - errorCounts(:) ./ countArray(:)) < 1e-12), ...
    "Figure431:CountMismatch", "BER is inconsistent with integer error counts.");
fprintf("Figure output written to: %s\n", figurePath);
end

function block = make_block(cfg, channel, snrDb)
infoBits = randi([0, 1], 1, cfg.dataSymbols);
codedBits = convolutional_encode(infoBits);
permutation = randperm(numel(codedBits));
inversePermutation = zeros(size(permutation));
inversePermutation(permutation) = 1:numel(permutation);
dataSymbols = qpsk_map(codedBits(permutation));
trainingSymbols = qpsk_map(randi([0, 1], 1, 2 * cfg.trainingSymbols));
tdDelay = min(cfg.feedforwardTaps - 1, channel.maxDelay);
tdTrainingSymbols = trainingSymbols;
noiseVariance = cfg.noisePowerFactor * 10^(-snrDb / 10);
branchCount = size(channel.impulses, 1);
trainingReceived = complex(zeros(branchCount, cfg.trainingSymbols));
tdTrainingReceived = complex(zeros(branchCount, numel(tdTrainingSymbols)));
dataReceived = complex(zeros(branchCount, cfg.dataSymbols));
for branchIndex = 1:branchCount
    impulse = channel.impulses(branchIndex, :).';
        pathDopplers = channel.pathDopplerHz(branchIndex, :);
        trainingClean = time_varying_channel(trainingSymbols, impulse, ...
            pathDopplers, 0, cfg.symbolRate, false);
        tdTrainingClean = time_varying_channel(tdTrainingSymbols, impulse, ...
            pathDopplers, 0, cfg.symbolRate, true);
        dataClean = time_varying_channel(dataSymbols, impulse, pathDopplers, ...
            cfg.trainingSymbols, cfg.symbolRate, true);
        trainingReceived(branchIndex, :) = trainingClean(1:cfg.trainingSymbols).' + ...
            sqrt(noiseVariance / 2) * (randn(1, cfg.trainingSymbols) + ...
            1j * randn(1, cfg.trainingSymbols));
        tdTrainingReceived(branchIndex, :) = tdTrainingClean.' + ...
            sqrt(noiseVariance / 2) * (randn(1, numel(tdTrainingSymbols)) + ...
            1j * randn(1, numel(tdTrainingSymbols)));
    dataReceived(branchIndex, :) = dataClean.' + ...
        sqrt(noiseVariance / 2) * (randn(1, cfg.dataSymbols) + ...
        1j * randn(1, cfg.dataSymbols));
end

Hestimate = estimate_channel_ls(trainingReceived, trainingSymbols, ...
    channel, cfg, noiseVariance);
Htrue = channel_frequency_response(channel, cfg.dataSymbols);
if strcmpi(string(cfg.channelEstimateMode), "perfect")
    Hestimate = Htrue;
end
interleavedBits = codedBits(permutation);
fixed = run_fdce(dataReceived, Hestimate, noiseVariance, infoBits, ...
    interleavedBits, permutation, inversePermutation, cfg);
fdda = run_fdda(dataReceived, trainingReceived, trainingSymbols, ...
    Hestimate, noiseVariance, infoBits, ...
    interleavedBits, permutation, inversePermutation, cfg);
tdda = run_tdda(dataReceived, tdTrainingReceived, tdTrainingSymbols, ...
    noiseVariance, infoBits, interleavedBits, permutation, inversePermutation, ...
    tdDelay, cfg);
block.errors = [tdda.errors; fixed.errors; fdda.errors];
block.codedErrors = [tdda.codedErrors; fixed.codedErrors; fdda.codedErrors];
block.channelNmse = channel_nmse(Hestimate, Htrue);
end

function output = run_fdce(received, Hestimate, noiseVariance, infoBits, ...
        transmittedBits, permutation, inversePermutation, cfg)
[branchCount, blockLength] = size(received);
Y = fft(received, [], 2);
softSymbols = complex(zeros(1, blockLength));
output.errors = zeros(1, cfg.outerIterations);
output.codedErrors = zeros(1, cfg.outerIterations);
for iteration = 1:cfg.outerIterations
    reliability = min(0.80, mean(abs(softSymbols).^2));
    W = fixed_mrc_weights(Hestimate, noiseVariance, reliability);
    estimate = softSymbols;
    for branchIndex = 1:branchCount
        estimate = estimate + ifft(W(branchIndex, :) .* ...
            (Y(branchIndex, :) - Hestimate(branchIndex, :) .* fft(softSymbols)));
    end
    effectiveNoise = equalizer_noise_variance(W, Hestimate, noiseVariance, reliability);
    output.codedErrors(iteration) = sum(qpsk_hard_bits(estimate) ~= transmittedBits);
    [infoLlr, codedPosterior, softCandidate, ~] = turbo_decoder(estimate, ...
        effectiveNoise, infoBits, permutation, inversePermutation);
    softSymbols = (1 - cfg.turboDamping) * softSymbols + ...
        cfg.turboDamping * softCandidate;
    output.errors(iteration) = sum((infoLlr < 0) ~= infoBits);
    output.posterior(iteration, :) = codedPosterior;
end
end

function output = run_fdda(received, trainingReceived, trainingSymbols, ...
        Hestimate, noiseVariance, infoBits, ...
        transmittedBits, permutation, inversePermutation, cfg)
[branchCount, blockLength] = size(received);
Y = fft(received, [], 2);
subblockCount = blockLength / cfg.subblockLength;
initialWeights = train_fd_weights(trainingReceived, trainingSymbols, ...
    Hestimate, blockLength, cfg, noiseVariance);
initialFeedback = sum(initialWeights .* Hestimate, 1) - 1;
W = repmat(initialWeights, 1, 1, subblockCount);
B = repmat(initialFeedback, subblockCount, 1);
softSymbols = complex(zeros(1, blockLength));
output.errors = zeros(1, cfg.outerIterations);
output.codedErrors = zeros(1, cfg.outerIterations);
for iteration = 1:cfg.outerIterations
    reliability = min(0.80, mean(abs(softSymbols).^2));
    estimate = complex(zeros(1, blockLength));
    effectiveNoise = 0;
    for subblockIndex = 1:subblockCount
        startIndex = (subblockIndex - 1) * cfg.subblockLength + 1;
        stopIndex = subblockIndex * cfg.subblockLength;
        subblockEstimate = fdda_estimate(Y, W(:, :, subblockIndex), ...
            B(subblockIndex, :), softSymbols);
        estimate(startIndex:stopIndex) = subblockEstimate(startIndex:stopIndex);
        effectiveNoise = effectiveNoise + equalizer_noise_variance( ...
            W(:, :, subblockIndex), Hestimate, noiseVariance, reliability);
    end
    effectiveNoise = effectiveNoise / subblockCount;
    output.codedErrors(iteration) = sum(qpsk_hard_bits(estimate) ~= transmittedBits);
    [infoLlr, codedPosterior, softCandidate, softExtrinsic] = turbo_decoder(estimate, ...
        effectiveNoise, infoBits, permutation, inversePermutation);
    adaptiveTarget = softCandidate;
    softSymbols = (1 - cfg.turboDamping) * softSymbols + ...
        cfg.turboDamping * softCandidate;
    softSpectrum = fft(softSymbols);
    for innerIndex = 1:cfg.innerIterations
        for subblockIndex = 1:subblockCount
            startIndex = (subblockIndex - 1) * cfg.subblockLength + 1;
            stopIndex = subblockIndex * cfg.subblockLength;
            errorTime = zeros(1, blockLength);
            errorTime(startIndex:stopIndex) = ...
                adaptiveTarget(startIndex:stopIndex) - estimate(startIndex:stopIndex);
            errorSpectrum = fft(errorTime);
            denominator = sum(abs(Y).^2, 1) + cfg.regularization;
            for branchIndex = 1:branchCount
                W(branchIndex, :, subblockIndex) = W(branchIndex, :, subblockIndex) + ...
                    cfg.fdUpdateStepScale * cfg.forwardStep * ...
                    conj(Y(branchIndex, :)) .* ...
                    errorSpectrum ./ denominator;
            end
            feedbackDenominator = abs(softSpectrum).^2 + cfg.regularization;
            B(subblockIndex, :) = B(subblockIndex, :) - ...
                cfg.feedbackStep * conj(softSpectrum) .* errorSpectrum ./ ...
                feedbackDenominator;
        end
    end
    output.errors(iteration) = sum((infoLlr < 0) ~= infoBits);
    output.posterior(iteration, :) = codedPosterior;
end
end

function output = run_tdda(received, trainingReceived, trainingSymbols, ...
        noiseVariance, infoBits, transmittedBits, permutation, inversePermutation, ...
        delay, cfg)
[branchCount, blockLength] = size(received);
tapCount = cfg.feedforwardTaps;
feedbackCount = cfg.feedbackTaps;
weights = complex(zeros(branchCount * tapCount + feedbackCount, 1));
for branchIndex = 1:branchCount
    offset = (branchIndex - 1) * tapCount;
    weights(offset + min(delay, tapCount - 1) + 1) = 1 / branchCount;
end
weights = train_td_weights(weights, trainingReceived, trainingSymbols, cfg, ...
    tapCount, feedbackCount, delay);
softSymbols = complex(zeros(1, blockLength));
output.errors = zeros(1, cfg.outerIterations);
output.codedErrors = zeros(1, cfg.outerIterations);
for iteration = 1:cfg.outerIterations
    estimate = complex(zeros(1, blockLength));
    for symbolIndex = 1:blockLength
        input = td_input(received, softSymbols, symbolIndex, tapCount, ...
            feedbackCount, delay);
        estimate(symbolIndex) = weights' * input;
    end
    decisionSymbols = qpsk_map(qpsk_hard_bits(estimate));
    effectiveNoise = max(noiseVariance, ...
        mean(abs(estimate - decisionSymbols).^2));
    output.codedErrors(iteration) = sum(qpsk_hard_bits(estimate) ~= transmittedBits);
    [infoLlr, codedPosterior, softCandidate, softExtrinsic] = turbo_decoder(estimate, ...
        effectiveNoise, infoBits, permutation, inversePermutation);
    adaptiveTarget = softCandidate;
    softSymbols = (1 - cfg.turboDamping) * softSymbols + ...
        cfg.turboDamping * softExtrinsic;
    for symbolIndex = 1:blockLength
        input = td_input(received, softSymbols, symbolIndex, tapCount, ...
            feedbackCount, delay);
        error = adaptiveTarget(symbolIndex) - weights' * input;
        weights = weights + cfg.timeStep * input * conj(error) / ...
            (real(input' * input) + cfg.regularization);
    end
    output.errors(iteration) = sum((infoLlr < 0) ~= infoBits);
    output.posterior(iteration, :) = codedPosterior;
end
end

function weights = train_td_weights(weights, received, training, cfg, ...
        tapCount, feedbackCount, delay)
weightCount = numel(weights);
design = complex(zeros(numel(training), weightCount));
target = training(:);
zeroFeedback = complex(zeros(size(training)));
for symbolIndex = 1:numel(training)
    input = td_input(received, zeroFeedback, symbolIndex, tapCount, ...
        feedbackCount, delay);
    design(symbolIndex, :) = input.';
end
conjugateWeights = (design' * design + cfg.regularization * eye(weightCount)) ...
    \ (design' * target);
weights = conj(conjugateWeights);
end

function input = td_input(received, softSymbols, symbolIndex, tapCount, ...
        feedbackCount, delay)
[branchCount, blockLength] = size(received);
input = complex(zeros(branchCount * tapCount + feedbackCount, 1));
for branchIndex = 1:branchCount
    offset = (branchIndex - 1) * tapCount;
    for tapIndex = 0:tapCount - 1
        index = mod(symbolIndex + delay - tapIndex - 1, blockLength) + 1;
        input(offset + tapIndex + 1) = received(branchIndex, index);
    end
end
for tapIndex = 1:feedbackCount
    index = mod(symbolIndex - tapIndex - 1, blockLength) + 1;
    input(branchCount * tapCount + tapIndex) = -softSymbols(index);
end
end

function estimate = fdda_estimate(Y, W, B, softSymbols)
estimate = ifft(-B .* fft(softSymbols));
for branchIndex = 1:size(Y, 1)
    estimate = estimate + ifft(W(branchIndex, :) .* Y(branchIndex, :));
end
end

function W = train_fd_weights(trainingReceived, trainingSymbols, Hestimate, ...
        blockLength, cfg, noiseVariance)
% Train the FDDA feed-forward weights from the known preamble.
[branchCount, trainingLength] = size(trainingReceived);
desired = [trainingSymbols, zeros(1, blockLength - trainingLength)];
desiredSpectrum = fft(desired);
trainingSpectrum = fft([trainingReceived, ...
    zeros(branchCount, blockLength - trainingLength)], [], 2);
W = fixed_mrc_weights(Hestimate, noiseVariance);
denominator = sum(abs(trainingSpectrum).^2, 1) + ...
    cfg.regularization + noiseVariance;
trainingStep = cfg.fdTrainingStepScale * cfg.forwardStep;
for iteration = 1:cfg.fdTrainingIterations
    estimateSpectrum = sum(W .* trainingSpectrum, 1);
    errorSpectrum = desiredSpectrum - estimateSpectrum;
    for branchIndex = 1:branchCount
        W(branchIndex, :) = W(branchIndex, :) + ...
            trainingStep * conj(trainingSpectrum(branchIndex, :)) .* ...
            errorSpectrum ./ denominator;
    end
end
end

function W = fixed_mrc_weights(Hestimate, noiseVariance, reliability)
if nargin < 3
    reliability = 0;
end
denominator = (1 - reliability) * sum(abs(Hestimate).^2, 1) + noiseVariance;
W = conj(Hestimate) ./ (denominator + eps);
end

function variance = equalizer_noise_variance(W, Hestimate, noiseVariance, reliability)
gain = sum(W .* Hestimate, 1);
residualVariance = noiseVariance * sum(abs(W).^2, 1) + ...
    (1 - reliability) * abs(gain - 1).^2;
variance = mean(residualVariance) / max(mean(abs(gain).^2), eps);
end

function [infoLlr, codedPosteriorInterleaved, softSymbols, softExtrinsic] = turbo_decoder( ...
        estimate, noiseVariance, infoBits, permutation, inversePermutation)
llrInterleaved = qpsk_llr(estimate, noiseVariance);
llrCoded = llrInterleaved(inversePermutation);
[infoLlr, codedPosterior] = bcjr_siso(llrCoded);
codedPosteriorInterleaved = codedPosterior(permutation);
codedExtrinsic = codedPosterior - llrCoded;
softExtrinsic = qpsk_soft(codedExtrinsic(permutation));
softSymbols = qpsk_soft(codedPosteriorInterleaved);
assert(numel(infoLlr) == numel(infoBits), ...
    "Figure431:DecoderLength", "Decoder output length is inconsistent.");
end

function llr = qpsk_llr(symbols, noiseVariance)
symbols = symbols(:).';
llr = zeros(1, 2 * numel(symbols));
llr(1:2:end) = 2 * sqrt(2) * real(symbols) / noiseVariance;
llr(2:2:end) = 2 * sqrt(2) * imag(symbols) / noiseVariance;
llr = max(-80, min(80, llr));
end

function symbols = qpsk_soft(llr)
llr = reshape(llr, 2, []);
symbols = (tanh(llr(1, :) / 2) + 1j * tanh(llr(2, :) / 2)) / sqrt(2);
end

function bits = qpsk_hard_bits(symbols)
symbols = symbols(:).';
bits = zeros(1, 2 * numel(symbols));
bits(1:2:end) = real(symbols) < 0;
bits(2:2:end) = imag(symbols) < 0;
end

function symbols = qpsk_map(bits)
bits = reshape(bits, 2, []);
symbols = ((1 - 2 * bits(1, :)) + 1j * (1 - 2 * bits(2, :))) / sqrt(2);
end

function coded = convolutional_encode(bits)
bits = bits(:).';
state = [0, 0];
coded = zeros(1, 2 * numel(bits));
for index = 1:numel(bits)
    bit = bits(index);
    coded(2 * index - 1) = mod(bit + state(2), 2);
    coded(2 * index) = mod(bit + state(1) + state(2), 2);
    state = [bit, state(1)];
end
end

function [informationLlr, codedLlr] = bcjr_siso(codedInputLlr)
[nextState, outputBits] = convolutional_trellis();
timeCount = numel(codedInputLlr) / 2;
stateCount = 4;
branch = zeros(timeCount, stateCount, 2);
for timeIndex = 1:timeCount
    for state = 1:stateCount
        for inputBit = 0:1
            bits = squeeze(outputBits(state, inputBit + 1, :)).';
            branch(timeIndex, state, inputBit + 1) = ...
                0.5 * sum((1 - 2 * bits) .* ...
                codedInputLlr(2 * timeIndex - 1:2 * timeIndex));
        end
    end
end
alpha = -inf(timeCount + 1, stateCount);
beta = -inf(timeCount + 1, stateCount);
alpha(1, 1) = 0;
beta(end, :) = 0;
for timeIndex = 1:timeCount
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            alpha(timeIndex + 1, next) = logadd(alpha(timeIndex + 1, next), ...
                alpha(timeIndex, state) + branch(timeIndex, state, inputBit + 1));
        end
    end
    alpha(timeIndex + 1, :) = alpha(timeIndex + 1, :) - max(alpha(timeIndex + 1, :));
end
for timeIndex = timeCount:-1:1
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            beta(timeIndex, state) = logadd(beta(timeIndex, state), ...
                branch(timeIndex, state, inputBit + 1) + beta(timeIndex + 1, next));
        end
    end
    beta(timeIndex, :) = beta(timeIndex, :) - max(beta(timeIndex, :));
end
informationLlr = zeros(1, timeCount);
codedLlr = zeros(1, 2 * timeCount);
for timeIndex = 1:timeCount
    inputMetric = [-inf, -inf];
    codeMetric = -inf(2, 2);
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            metric = alpha(timeIndex, state) + branch(timeIndex, state, inputBit + 1) + ...
                beta(timeIndex + 1, next);
            inputMetric(inputBit + 1) = logadd(inputMetric(inputBit + 1), metric);
            bits = squeeze(outputBits(state, inputBit + 1, :)).';
            for codeIndex = 1:2
                codeMetric(bits(codeIndex) + 1, codeIndex) = ...
                    logadd(codeMetric(bits(codeIndex) + 1, codeIndex), metric);
            end
        end
    end
    informationLlr(timeIndex) = inputMetric(1) - inputMetric(2);
    codedLlr(2 * timeIndex - 1) = codeMetric(1, 1) - codeMetric(2, 1);
    codedLlr(2 * timeIndex) = codeMetric(1, 2) - codeMetric(2, 2);
end
end

function value = logadd(left, right)
maximum = max(left, right);
if isinf(maximum)
    value = maximum;
else
    value = maximum + log1p(exp(min(left, right) - maximum));
end
end

function [nextState, outputBits] = convolutional_trellis()
nextState = zeros(4, 2);
outputBits = zeros(4, 2, 2);
for state = 0:3
    memory = [bitget(state, 2), bitget(state, 1)];
    for inputBit = 0:1
        nextState(state + 1, inputBit + 1) = inputBit * 2 + memory(1) + 1;
        outputBits(state + 1, inputBit + 1, :) = [ ...
            mod(inputBit + memory(2), 2), ...
            mod(inputBit + memory(1) + memory(2), 2)];
    end
end
end

function H = estimate_channel_ls(received, training, channel, cfg, noiseVariance)
tapCount = min(channel.maxDelay + 1, cfg.trainingSymbols - 1);
T = zeros(cfg.trainingSymbols, tapCount);
for tapIndex = 0:tapCount - 1
    T(tapIndex + 1:end, tapIndex + 1) = training(1:end - tapIndex);
end
H = complex(zeros(size(received, 1), cfg.dataSymbols));
for branchIndex = 1:size(received, 1)
    y = received(branchIndex, :).';
    h = (T' * T + noiseVariance * cfg.trainingRegularization * eye(tapCount)) ...
        \ (T' * y);
    H(branchIndex, :) = fft([h; zeros(cfg.dataSymbols - tapCount, 1)]).';
end
end

function H = channel_frequency_response(channel, blockLength)
H = fft(channel.impulses, blockLength, 2);
end

function channel = build_channel(cfg)
bellhopPath = fullfile(cfg.bellhopRoot, "windows-bin-20201102", "bellhop.exe");
if strcmpi(string(cfg.channelSource), "bellhop") && isfile(bellhopPath)
    try
        channel = bellhop_two_receiver_channel(cfg);
        return;
    catch exception
        warning("Figure431:BellhopFallback", ...
            "Bellhop failed (%s); using the documented paper-ray fallback.", exception.message);
    end
end
channel = paper_ray_channel(cfg);
end

function channel = bellhop_two_receiver_channel(cfg)
readerDirectory = fullfile(cfg.bellhopRoot, "Matlab", "ReadWrite");
assert(isfile(fullfile(readerDirectory, "read_arrivals_asc.m")), ...
    "Bellhop arrival reader was not found.");
outputDir = fullfile(cfg.outputDir, "bellhop_figure431");
if ~exist(outputDir, "dir")
    mkdir(outputDir);
end
rootName = "chapter4_figure431";
environmentFile = fullfile(outputDir, rootName + ".env");
write_bellhop_environment(environmentFile, cfg);
oldDirectory = pwd;
cleanup = onCleanup(@() cd(oldDirectory));
cd(outputDir);
bellhopExecutable = fullfile(cfg.bellhopRoot, "windows-bin-20201102", "bellhop.exe");
[status, commandOutput] = system(sprintf('"%s" %s', bellhopExecutable, rootName));
assert(status == 0, "Bellhop failed: %s", commandOutput);
addpath(readerDirectory);
[arrivals, positions] = read_arrivals_asc(rootName + ".arr");
receiverCount = numel(cfg.receiverDepths);
impulses = complex(zeros(receiverCount, cfg.maxDelaySymbols + 1));
for branchIndex = 1:receiverCount
    arrival = arrivals(1, branchIndex, 1);
    delays = real(double(arrival.delay(:).'));
    gains = double(arrival.A(:).');
    relativeDelay = delays - min(delays);
    delaySymbols = round(relativeDelay * cfg.symbolRate);
    keep = delaySymbols <= cfg.maxDelaySymbols;
    for pathIndex = find(keep)
        impulses(branchIndex, delaySymbols(pathIndex) + 1) = ...
            impulses(branchIndex, delaySymbols(pathIndex) + 1) + gains(pathIndex);
    end
end
energy = sqrt(mean(sum(abs(impulses).^2, 2)));
assert(energy > 0, "Bellhop returned an empty two-receiver channel.");
impulses = impulses / energy;
channel.impulses = impulses;
channel.pathDopplerHz = make_path_dopplers(impulses, cfg.maxDopplerHz);
channel.maxDelay = cfg.maxDelaySymbols;
channel.source = "Bellhop";
channel.environmentFile = environmentFile;
channel.arrivalsFile = fullfile(outputDir, rootName + ".arr");
channel.receiverDepths = double(positions.r.z(:).');
channel.pathDelayUnit = "symbol intervals";
end

function write_bellhop_environment(fileName, cfg)
fid = fopen(fileName, "w");
assert(fid >= 0, "Cannot create Bellhop environment file.");
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, "'Chapter 4 Figure 4-31 shallow-water channel'\n");
fprintf(fid, "%.6f\n", cfg.carrierHz);
fprintf(fid, "1\n'CVW'\n");
fprintf(fid, "101 0.0 %.6f\n", cfg.waterDepth);
fprintf(fid, "0.0 1500.0 0.0 1.0 0.0 /\n");
fprintf(fid, "%.6f 1490.0 /\n", cfg.waterDepth);
fprintf(fid, "'A' 0.0\n");
fprintf(fid, "%.6f 1700.0 0.0 1.8 0.8 /\n", cfg.waterDepth);
fprintf(fid, "1\n%.6f /\n", cfg.sourceDepth);
fprintf(fid, "%d\n", numel(cfg.receiverDepths));
fprintf(fid, "%.6f ", cfg.receiverDepths);
fprintf(fid, "/\n1\n%.6f /\n", cfg.rangeKm);
fprintf(fid, "'A'\n2000\n-80.0 80.0 /\n");
fprintf(fid, "0.0 %.6f %.6f\n", 1.2 * cfg.waterDepth, cfg.rangeKm + 0.5);
end

function channel = paper_ray_channel(cfg)
delays = cfg.paperRayDelays;
base = cfg.paperRayGains;
assert(numel(delays) == numel(base) && all(delays >= 0) && ...
    all(delays <= cfg.maxDelaySymbols), ...
    "Figure431:InvalidPaperRay", ...
    "Paper-ray delays and gains are inconsistent with maxDelaySymbols.");
impulses = complex(zeros(2, cfg.maxDelaySymbols + 1));
for branchIndex = 1:2
    pathIndex = 1:numel(delays);
    phase = 0.31 * branchIndex .* pathIndex + 0.17 * pathIndex + ...
        0.03 * delays;
    impulses(branchIndex, delays + 1) = base .* exp(1j * phase);
end
impulses = impulses / sqrt(mean(sum(abs(impulses).^2, 2)));
channel.impulses = impulses;
channel.pathDopplerHz = make_path_dopplers(impulses, cfg.maxDopplerHz);
channel.maxDelay = cfg.maxDelaySymbols;
channel.source = "paper-ray-fallback";
channel.environmentFile = "";
channel.arrivalsFile = "";
channel.receiverDepths = cfg.receiverDepths;
channel.pathDelayUnit = "symbol intervals";
end

function plot_reference_figure(cfg, methodNames, ber, fileName)
figureHandle = figure("Color", "w", "Position", [100, 100, 1000, 700], "Visible", "off");
hold on;
markers = ["v", "o", "d", "s", "*", ">", "<", "p", "h"];
colors = [0.05, 0.25, 0.65; 0.75, 0.20, 0.10; 0.10, 0.50, 0.25];
lineStyles = repmat("-", 1, 9);
curveColors = zeros(9, 3);
if strcmpi(string(cfg.berMetric), "coded")
    markers = [">", "o", "d", "s", "*", "*", ">", "o", "d"];
    lineStyles(1:3) = "--";
    lineStyles(7:9) = "--";
    curveColors = [0.85, 0.15, 0.10; 0.10, 0.25, 0.65; 0.05, 0.05, 0.05; ...
        0.85, 0.15, 0.10; 0.10, 0.25, 0.65; 0.05, 0.05, 0.05; ...
        0.45, 0.20, 0.55; 0.20, 0.65, 0.75; 0.30, 0.65, 0.20];
else
    for methodIndex = 1:3
        curveColors((methodIndex - 1) * 3 + (1:3), :) = ...
            repmat(colors(methodIndex, :), 3, 1);
    end
end
legendEntries = strings(0, 1);
curveIndex = 0;
for methodIndex = 1:numel(methodNames)
    for iteration = 1:cfg.outerIterations
        curveIndex = curveIndex + 1;
        curve = squeeze(ber(methodIndex, iteration, :)).';
        semilogy(cfg.snrDb, max(curve, 1e-5), lineStyles(curveIndex), ...
            "Color", curveColors(curveIndex, :), "Marker", markers(curveIndex), ...
            "LineWidth", 1.4, "MarkerSize", 6);
        legendEntries(end + 1) = sprintf("%s, I_{out}=%d", methodNames(methodIndex), iteration);
    end
end
grid on;
box on;
set(gca, "YScale", "log");
snrMin = min(cfg.snrDb);
snrMax = max(cfg.snrDb);
if snrMax == snrMin
    snrMin = snrMin - 1;
    snrMax = snrMax + 1;
end
xlim([snrMin, snrMax]);
ylim([1e-4, 1]);
xlabel("SNR (dB)");
ylabel("BER");
title("图4-31 三种Turbo均衡方法的BER性能对比");
if strcmpi(string(cfg.berMetric), "coded")
    ylim([1e-5, 1]);
    title("图4-32 FDDA-TEQ和其他方法编码BER性能对比");
else
    title("图4-31 三种Turbo均衡方法的BER性能对比");
end
legend(legendEntries, "Location", "southwest", "NumColumns", 2);
set(gca, "FontName", "Microsoft YaHei", "FontSize", 11);
exportgraphics(figureHandle, fileName, "Resolution", 220);
close(figureHandle);
end

function count = frame_count_at(frameCount, index)
if isscalar(frameCount)
    count = frameCount;
else
    count = frameCount(index);
end
end

function output = merge_options(defaults, options)
output = defaults;
names = fieldnames(options);
for index = 1:numel(names)
    output.(names{index}) = options.(names{index});
end
end

function value = channel_nmse(estimate, reference)
value = sum(abs(estimate(:) - reference(:)).^2) / max(sum(abs(reference(:)).^2), eps);
end

function dopplers = make_path_dopplers(impulses, maximumDoppler)
[branchCount, tapCount] = size(impulses);
dopplers = zeros(branchCount, tapCount);
for branchIndex = 1:branchCount
    tapIndex = 0:tapCount - 1;
    dopplers(branchIndex, :) = maximumDoppler * sin( ...
        0.37 * branchIndex + 0.083 * tapIndex);
end
end

function output = time_varying_channel(input, impulse, dopplers, startSymbol, ...
        symbolRate, circularMode)
input = input(:);
sampleCount = numel(input);
tapIndices = find(abs(impulse) > 0) - 1;
output = complex(zeros(sampleCount, 1));
time = (startSymbol + (0:sampleCount - 1)).' / symbolRate;
for tapIndex = tapIndices(:).'
    coefficient = impulse(tapIndex + 1) * exp(1j * 2 * pi * ...
        dopplers(tapIndex + 1) * time);
    if circularMode
        sourceIndex = mod((0:sampleCount - 1).' - tapIndex, sampleCount) + 1;
        output = output + coefficient .* input(sourceIndex);
    else
        sourceIndex = (1:sampleCount).' - tapIndex;
        valid = sourceIndex >= 1;
        output(valid) = output(valid) + coefficient(valid) .* input(sourceIndex(valid));
    end
end
end
