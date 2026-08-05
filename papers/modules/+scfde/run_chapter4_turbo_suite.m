function results = run_chapter4_turbo_suite(options, simulationDir)
%RUN_CHAPTER4_TURBO_SUITE Selectable Chapter 4 iterative equalizers.

defaults.infoBits = 64;
defaults.frameCount = 8;
defaults.iterations = 4;
defaults.snrList = -8:2:4;
defaults.snrDb = -2;
defaults.randomSeed = 20260724;
defaults.makePlot = true;
defaults.blmsStep = 0.06;
defaults.blmsLeakage = 1e-3;
defaults.blmsRegularization = 1e-3;
defaults.tdNlmsStep = 0.35;
defaults.tdAdaptiveTaps = 16;
defaults.turboDamping = 0.75;
defaults.channelEstimationErrorScale = 0.15;
defaults.fdceChannelEstimationErrorScale = [];
defaults.adaptiveChannelEstimationErrorScale = [];
defaults.tddaChannelEstimationErrorScale = [];
defaults.fddaChannelEstimationErrorScale = [];
defaults.methods = "all";
defaults.decoderMethods = "all";
defaults.baselineDecoder = "Log-MAP";
defaults.channel = [1, 0.72 * exp(1j * 0.45), ...
    0.43 * exp(-1j * 0.9), 0.22 * exp(1j * 1.5)];
defaults.outputDir = fullfile(simulationDir, "results");
cfg = merge_options(defaults, options);
cfg.channel = cfg.channel(:).' / norm(cfg.channel);
if isempty(cfg.fdceChannelEstimationErrorScale)
    cfg.fdceChannelEstimationErrorScale = cfg.channelEstimationErrorScale;
end
if isempty(cfg.adaptiveChannelEstimationErrorScale)
    cfg.adaptiveChannelEstimationErrorScale = ...
        cfg.channelEstimationErrorScale;
end
if isempty(cfg.tddaChannelEstimationErrorScale)
    cfg.tddaChannelEstimationErrorScale = ...
        cfg.adaptiveChannelEstimationErrorScale;
end
if isempty(cfg.fddaChannelEstimationErrorScale)
    cfg.fddaChannelEstimationErrorScale = ...
        cfg.adaptiveChannelEstimationErrorScale;
end

availableMethods = ["TD-Turbo-MAP", "TD-Turbo-Log-MAP", ...
    "TD-Turbo-Max-Log-MAP", "FD-DFE", "FD-Turbo-Log-MAP", ...
    "FD-Turbo-Max-Log-MAP", "TF-Turbo-Log-MAP", ...
    "BiTF-Turbo-Log-MAP", "BLMS-TF-Turbo", "TDDA-TEQ", ...
    "FDDA-TEQ", "FDDA-DFE-TEQ"];
availableDecoderMethods = ["MAP", "Log-MAP", "Max-Log-MAP"];
methodIndices = select_method_indices(availableMethods, cfg.methods, ...
    "iterative-equalization");
decoderIndices = select_method_indices(availableDecoderMethods, ...
    cfg.decoderMethods, "BCJR decoder");
cfg.baselineDecoder = canonical_decoder_mode(cfg.baselineDecoder);

assert(cfg.infoBits > 0 && mod(cfg.infoBits, 1) == 0, ...
    "SCFDE:InvalidInformationLength", "infoBits must be a positive integer.");
assert(all(cfg.frameCount > 0) && ...
    (isscalar(cfg.frameCount) || numel(cfg.frameCount) == numel(cfg.snrList)) ...
    && cfg.iterations > 0, ...
    "SCFDE:InvalidIterationConfig", ...
    "frameCount and iterations must be positive.");
assert(cfg.turboDamping > 0 && cfg.turboDamping <= 1, ...
    "SCFDE:InvalidTurboDamping", "turboDamping must be in (0, 1].");
assert(cfg.tdAdaptiveTaps > 0 && cfg.tdAdaptiveTaps <= 2 * cfg.infoBits, ...
    "SCFDE:InvalidAdaptiveTapCount", ...
    "tdAdaptiveTaps must be positive and no longer than the coded block.");

rng(cfg.randomSeed, "twister");
allMethodBer = zeros(numel(availableMethods), numel(cfg.snrList));
allMethodIterationBer = zeros(numel(availableMethods), cfg.iterations, ...
    numel(cfg.snrList));
allMethodIterationErrorCounts = zeros(size(allMethodIterationBer));
bitCountsBySnr = zeros(1, numel(cfg.snrList));
allDecoderBer = zeros(numel(availableDecoderMethods), numel(cfg.snrList));
for snrIndex = 1:numel(cfg.snrList)
    methodErrors = zeros(numel(availableMethods), 1);
    methodIterationErrors = zeros(numel(availableMethods), cfg.iterations);
    decoderErrors = zeros(numel(availableDecoderMethods), 1);
    totalBits = 0;
    if isscalar(cfg.frameCount)
        framesAtSnr = cfg.frameCount;
    else
        framesAtSnr = cfg.frameCount(snrIndex);
    end
    for frameIndex = 1:framesAtSnr
        frame = run_frame(cfg, cfg.snrList(snrIndex));
        methodErrors = methodErrors + frame.methodErrors;
        methodIterationErrors = methodIterationErrors + ...
            frame.methodCurves * cfg.infoBits;
        decoderErrors = decoderErrors + frame.decoderErrors;
        totalBits = totalBits + cfg.infoBits;
    end
    allMethodBer(:, snrIndex) = methodErrors / totalBits;
    allMethodIterationBer(:, :, snrIndex) = ...
        methodIterationErrors / totalBits;
    allMethodIterationErrorCounts(:, :, snrIndex) = methodIterationErrors;
    bitCountsBySnr(snrIndex) = totalBits;
    allDecoderBer(:, snrIndex) = decoderErrors / totalBits;
end

example = run_frame(cfg, cfg.snrDb);
results.config = cfg;
results.availableMethods = availableMethods;
results.methodIndices = methodIndices;
results.methodNames = availableMethods(methodIndices);
results.methods = results.methodNames;
results.ber = allMethodBer(methodIndices, :);
results.allMethodBer = allMethodBer;
results.allMethodIterationBer = allMethodIterationBer;
results.allMethodIterationErrorCounts = allMethodIterationErrorCounts;
results.bitCountsBySnr = bitCountsBySnr;
results.methodIterationBerBySnr = ...
    allMethodIterationBer(methodIndices, :, :);
results.methodIterationErrorCountsBySnr = ...
    allMethodIterationErrorCounts(methodIndices, :, :);
results.availableDecoderMethods = availableDecoderMethods;
results.decoderIndices = decoderIndices;
results.decoderNames = availableDecoderMethods(decoderIndices);
results.decoderBer = allDecoderBer(decoderIndices, :);
results.allDecoderBer = allDecoderBer;
results.snrList = cfg.snrList;
results.example = example;
results.methodIterationBer = example.methodCurves(methodIndices, :);
results.methodTraces = example.methodTraces(methodIndices);
results.outputPath = "";
results.figurePaths = strings(0, 1);

fprintf("\n===== Chapter 4 iterative equalization =====\n");
fprintf("Information bits=%d, iterations=%d, convolutional code rate=1/2\n", ...
    cfg.infoBits, cfg.iterations);
for methodIndex = methodIndices
    fprintf("%-28s BER@%.1f dB=%.5g\n", availableMethods(methodIndex), ...
        cfg.snrDb, example.methodErrors(methodIndex) / cfg.infoBits);
end
for decoderIndex = decoderIndices
    fprintf("%-28s initial-decoder BER=%.5g\n", ...
        availableDecoderMethods(decoderIndex), ...
        example.decoderErrors(decoderIndex) / cfg.infoBits);
end

if cfg.makePlot
    results.outputPath = plot_results(results);
    results.figurePaths = [string(results.outputPath); ...
        plot_turbo_exchange(results)];
    adaptivePath = plot_frequency_adaptive_blms(results);
    if strlength(adaptivePath) > 0
        results.figurePaths = [results.figurePaths; adaptivePath];
    end
end
end

function out = run_frame(cfg, snrDb)
info = randi([0, 1], 1, cfg.infoBits);
coded = convolutional_encode(info);
N = numel(coded);
permutation = randperm(N);
inversePermutation(permutation) = 1:N;
interleaved = coded(permutation);
transmitted = 1 - 2 * interleaved;

channel = [cfg.channel, zeros(1, N - numel(cfg.channel))];
H = fft(channel);
X = fft(transmitted);
noiseVariance = 10^(-snrDb / 10);
received = ifft(H .* X);
received = received + sqrt(noiseVariance / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));
Y = fft(received);
channelEstimateNoise = randn(size(H)) + 1j * randn(size(H));
Htdda = H + sqrt(noiseVariance * ...
    cfg.tddaChannelEstimationErrorScale / 2) * channelEstimateNoise;
Hinitial = H + sqrt(noiseVariance * ...
    cfg.fddaChannelEstimationErrorScale / 2) * channelEstimateNoise;
Hfdce = H + sqrt(noiseVariance * ...
    cfg.fdceChannelEstimationErrorScale / 2) * channelEstimateNoise;
initial = ifft(normalized_mmse(Hinitial, noiseVariance) .* Y);
initialLlr = 2 * real(initial) / noiseVariance;

[mapInfo, ~] = bcjr_siso_decode(initialLlr(inversePermutation), "MAP");
[logMapInfo, ~] = bcjr_siso_decode(initialLlr(inversePermutation), "Log-MAP");
[maxLogInfo, ~] = bcjr_siso_decode(initialLlr(inversePermutation), ...
    "Max-Log-MAP");

channelMatrix = circulant_channel(cfg.channel, N);
timeEqualizer = (channelMatrix' * channelMatrix + ...
    noiseVariance * eye(N)) \ channelMatrix';

[tdMapBits, tdMapCurve, tdMapTrace] = iterate_time_turbo(received, ...
    channelMatrix, timeEqualizer, noiseVariance, info, permutation, ...
    inversePermutation, cfg, "MAP");
[tdLogBits, tdLogCurve, tdLogTrace] = iterate_time_turbo(received, ...
    channelMatrix, timeEqualizer, noiseVariance, info, permutation, ...
    inversePermutation, cfg, "Log-MAP");
[tdMaxBits, tdMaxCurve, tdMaxTrace] = iterate_time_turbo(received, ...
    channelMatrix, timeEqualizer, noiseVariance, info, permutation, ...
    inversePermutation, cfg, "Max-Log-MAP");
[fdDfeBits, fdDfeCurve, fdDfeTrace] = frequency_dfe_baseline(Y, Hfdce, ...
    noiseVariance, info, inversePermutation, cfg);
[fdLogBits, fdLogCurve, fdLogTrace] = iterate_frequency_turbo(Y, Hfdce, ...
    H, noiseVariance, info, permutation, inversePermutation, cfg, ...
    "Log-MAP", false);
[fdMaxBits, fdMaxCurve, fdMaxTrace] = iterate_frequency_turbo(Y, Hfdce, ...
    H, noiseVariance, info, permutation, inversePermutation, cfg, ...
    "Max-Log-MAP", false);
[tfBits, tfCurve, tfTrace] = iterate_time_frequency_turbo(received, Y, ...
    channelMatrix, timeEqualizer, Hinitial, H, noiseVariance, info, ...
    permutation, inversePermutation, cfg, false, false);
[biTfBits, biTfCurve, biTfTrace] = iterate_time_frequency_turbo(received, Y, ...
    channelMatrix, timeEqualizer, Hinitial, H, noiseVariance, info, ...
    permutation, inversePermutation, cfg, true, false);
[blmsBits, blmsCurve, blmsTrace] = iterate_time_frequency_turbo(received, Y, ...
    channelMatrix, timeEqualizer, Hinitial, H, noiseVariance, info, ...
    permutation, inversePermutation, cfg, false, true);
[tdAdaptiveBits, tdAdaptiveCurve, tdAdaptiveTrace] = ...
    iterate_td_nlms_turbo(received, Y, Htdda, H, noiseVariance, info, ...
    permutation, inversePermutation, cfg);
[fdAdaptiveBits, fdAdaptiveCurve, fdAdaptiveTrace] = ...
    iterate_frequency_turbo(Y, Hinitial, H, noiseVariance, info, ...
    permutation, inversePermutation, cfg, "Log-MAP", true);
[fdAdaptiveDfeBits, fdAdaptiveDfeCurve, fdAdaptiveDfeTrace] = ...
    iterate_fd_blms_turbo(Y, Hinitial, H, noiseVariance, info, permutation, ...
    inversePermutation, cfg, true);

out.methodErrors = [sum(tdMapBits ~= info); sum(tdLogBits ~= info); ...
    sum(tdMaxBits ~= info); sum(fdDfeBits ~= info); sum(fdLogBits ~= info); ...
    sum(fdMaxBits ~= info); sum(tfBits ~= info); sum(biTfBits ~= info); ...
    sum(blmsBits ~= info); sum(tdAdaptiveBits ~= info); ...
    sum(fdAdaptiveBits ~= info); sum(fdAdaptiveDfeBits ~= info)];
out.decoderErrors = [sum((mapInfo < 0) ~= info); ...
    sum((logMapInfo < 0) ~= info); sum((maxLogInfo < 0) ~= info)];
out.methodCurves = [tdMapCurve; tdLogCurve; tdMaxCurve; fdDfeCurve; ...
    fdLogCurve; fdMaxCurve; tfCurve; biTfCurve; blmsCurve; ...
    tdAdaptiveCurve; fdAdaptiveCurve; fdAdaptiveDfeCurve];
out.methodTraces = {tdMapTrace, tdLogTrace, tdMaxTrace, fdDfeTrace, ...
    fdLogTrace, fdMaxTrace, tfTrace, biTfTrace, blmsTrace, ...
    tdAdaptiveTrace, fdAdaptiveTrace, fdAdaptiveDfeTrace};
out.info = info;
out.initial = initial;
out.H = H;
out.Hinitial = Hinitial;
out.Hblms = blmsTrace.finalChannel;
end

function [bits, curve, trace] = iterate_time_turbo(received, channelMatrix, ...
        timeEqualizer, noiseVariance, info, permutation, inversePermutation, ...
        cfg, decoderMode)
N = numel(received);
softSymbols = zeros(N, 1);
curve = zeros(1, cfg.iterations);
trace = initialize_trace(cfg.iterations, N, []);
for iteration = 1:cfg.iterations
    estimate = softSymbols + timeEqualizer * ...
        (received(:) - channelMatrix * softSymbols);
    equalizerLlr = 2 * real(estimate).'/noiseVariance;
    equalizerInput = equalizerLlr(inversePermutation);
    [informationLlr, codedLlr] = bcjr_siso_decode( ...
        equalizerInput, decoderMode);
    decoderExtrinsic = codedLlr - equalizerInput;
    decoderLlr = decoderExtrinsic(permutation);
    decoderPosterior = codedLlr(permutation);
    candidate = tanh(decoderPosterior / 2).';
    softSymbols = (1 - cfg.turboDamping) * softSymbols + ...
        cfg.turboDamping * candidate;
    bits = informationLlr < 0;
    curve(iteration) = mean(bits ~= info);
    trace = save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, []);
end
trace.finalChannel = [];
end

function [bits, curve, trace] = frequency_dfe_baseline(Y, H, ...
        noiseVariance, info, inversePermutation, cfg)
N = numel(Y);
feedforward = normalized_mmse(H, noiseVariance);
linearEstimate = ifft(feedforward .* Y);
initialDecision = hard_bpsk(linearEstimate);
feedback = feedforward .* H - 1;
estimate = ifft(feedforward .* Y - feedback .* fft(initialDecision));
equalizerLlr = 2 * real(estimate) / noiseVariance;
[informationLlr, codedLlr] = bcjr_siso_decode( ...
    equalizerLlr(inversePermutation), cfg.baselineDecoder);
bits = informationLlr < 0;
curve = mean(bits ~= info) * ones(1, cfg.iterations);
trace = initialize_trace(cfg.iterations, N, []);
for iteration = 1:cfg.iterations
    trace = save_trace(trace, iteration, equalizerLlr, codedLlr, ...
        tanh(codedLlr / 2).', []);
end
trace.finalChannel = H;
end

function [bits, curve, trace] = iterate_frequency_turbo(Y, Hest, ...
        Hreference, noiseVariance, info, permutation, inversePermutation, ...
        cfg, decoderMode, adaptiveChannel)
N = numel(Y);
softSymbols = zeros(1, N);
curve = zeros(1, cfg.iterations);
trace = initialize_trace(cfg.iterations, N, Hest);
for iteration = 1:cfg.iterations
    rho = min(0.995, mean(abs(softSymbols).^2));
    [feedforward, feedback] = fd_ibdfe_weights(Hest, noiseVariance, rho);
    estimate = ifft(feedforward .* Y - feedback .* fft(softSymbols));
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    equalizerInput = equalizerLlr(inversePermutation);
    [informationLlr, codedLlr] = bcjr_siso_decode( ...
        equalizerInput, decoderMode);
    decoderExtrinsic = codedLlr - equalizerInput;
    decoderLlr = decoderExtrinsic(permutation);
    decoderPosterior = codedLlr(permutation);
    candidate = tanh(decoderPosterior / 2);
    softSymbols = (1 - cfg.turboDamping) * softSymbols + ...
        cfg.turboDamping * candidate;
    if adaptiveChannel
        softSpectrum = fft(softSymbols);
        innovation = Y - Hest .* softSpectrum;
        Hest = Hest + cfg.blmsStep * conj(softSpectrum) .* innovation ./ ...
            (abs(softSpectrum).^2 + noiseVariance * N);
    end
    bits = informationLlr < 0;
    curve(iteration) = mean(bits ~= info);
    trace = save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, channel_nmse(Hest, Hreference));
end
trace.finalChannel = Hest;
end

function [feedforward, feedback] = fd_ibdfe_weights(Hest, noiseVariance, rho)
% (4-56): w_k = h_k*(1+b_k)/(σ²+|h_k|²)
% (4-57): b_k = [λ(σ²+|h_k|²)−σ²]/[(σ²+|h_k|²)−ρ|h_k|²]
% (4-58): λ = σ²·Σ[1/D_k] / Σ[(σ²+|h_k|²)/D_k]，对应 Σ_k b_k = 0 约束
denominator = (noiseVariance + abs(Hest).^2) - rho * abs(Hest).^2;
lambda = noiseVariance * sum(1 ./ max(denominator, eps)) / ...
    max(sum((noiseVariance + abs(Hest).^2) ./ max(denominator, eps)), eps);
feedback = (lambda * (noiseVariance + abs(Hest).^2) - noiseVariance) ./ ...
    max(denominator, eps);
feedforward = conj(Hest) .* (1 + feedback) ./ ...
    (noiseVariance + abs(Hest).^2);
end

function [bits, curve, trace] = iterate_time_frequency_turbo(received, Y, ...
        channelMatrix, timeEqualizer, Hest, Hreference, noiseVariance, ...
        info, permutation, inversePermutation, cfg, bidirectional, adaptiveChannel)
N = numel(received);
softSymbols = zeros(1, N);
curve = zeros(1, cfg.iterations);
trace = initialize_trace(cfg.iterations, N, Hest);
if bidirectional
    reverseChannel = rot90(channelMatrix, 2);
    reverseEqualizer = (reverseChannel' * reverseChannel + ...
        noiseVariance * eye(N)) \ reverseChannel';
end
for iteration = 1:cfg.iterations
    timeEstimate = softSymbols.' + timeEqualizer * ...
        (received(:) - channelMatrix * softSymbols.');
    rho = min(0.995, mean(abs(softSymbols).^2));
    [feedforward, feedback] = fd_ibdfe_weights(Hest, noiseVariance, rho);
    frequencyEstimate = ifft(feedforward .* Y - feedback .* fft(softSymbols));
    estimate = 0.5 * timeEstimate.' + 0.5 * frequencyEstimate;
    if bidirectional
        reverseSoft = fliplr(softSymbols).';
        reverseReceived = flipud(received(:));
        reverseEstimate = reverseSoft + reverseEqualizer * ...
            (reverseReceived - reverseChannel * reverseSoft);
        estimate = 0.5 * estimate + 0.5 * fliplr(reverseEstimate.');
    end
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    equalizerInput = equalizerLlr(inversePermutation);
    [informationLlr, codedLlr] = bcjr_siso_decode( ...
        equalizerInput, "Log-MAP");
    decoderExtrinsic = codedLlr - equalizerInput;
    decoderLlr = decoderExtrinsic(permutation);
    decoderPosterior = codedLlr(permutation);
    candidate = tanh(decoderPosterior / 2);
    softSymbols = (1 - cfg.turboDamping) * softSymbols + ...
        cfg.turboDamping * candidate;
    if adaptiveChannel
        softSpectrum = fft(softSymbols);
        innovation = Y - Hest .* softSpectrum;
        Hest = Hest + cfg.blmsStep * conj(softSpectrum) .* innovation ./ ...
            (abs(softSpectrum).^2 + noiseVariance * N);
    end
    bits = informationLlr < 0;
    curve(iteration) = mean(bits ~= info);
    trace = save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, channel_nmse(Hest, Hreference));
end
trace.finalChannel = Hest;
end

function [bits, curve, trace] = iterate_td_nlms_turbo(received, Y, ...
        Hinitial, Hreference, noiseVariance, info, permutation, ...
        inversePermutation, cfg)
N = numel(received);
tapCount = min(cfg.tdAdaptiveTaps, N);
initialImpulse = ifft(normalized_mmse(Hinitial, noiseVariance));
weights = initialImpulse(1:tapCount).';
referenceWeights = normalized_mmse(Hreference, noiseVariance);
softSymbols = initial_soft_feedback(Y, Hinitial, noiseVariance, ...
    permutation, inversePermutation);
curve = zeros(1, cfg.iterations);
trace = initialize_trace(cfg.iterations, N, []);
for iteration = 1:cfg.iterations
    residual = zeros(1, N);
    for sampleIndex = 1:N
        inputIndices = mod(sampleIndex - 1 - (0:tapCount - 1), N) + 1;
        inputVector = received(inputIndices).';
        adaptiveOutput = weights' * inputVector;
        residual(sampleIndex) = softSymbols(sampleIndex) - adaptiveOutput;
        weights = weights + cfg.tdNlmsStep * inputVector * ...
            conj(residual(sampleIndex)) / ...
            (real(inputVector' * inputVector) + cfg.blmsRegularization);
    end
    estimate = zeros(1, N);
    for sampleIndex = 1:N
        inputIndices = mod(sampleIndex - 1 - (0:tapCount - 1), N) + 1;
        inputVector = received(inputIndices).';
        estimate(sampleIndex) = weights' * inputVector;
    end
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    [bits, decoderLlr, softSymbols] = decoder_feedback(equalizerLlr, ...
        permutation, inversePermutation, softSymbols, cfg);
    weightSpectrum = fft([weights.', zeros(1, N - tapCount)]);
    curve(iteration) = mean(bits ~= info);
    trace = save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, []);
    trace.frequencyWeights(iteration, :) = weightSpectrum;
    trace.weightNmse(iteration) = channel_nmse(weightSpectrum, referenceWeights);
    trace.errorPower(iteration) = mean(abs(residual).^2);
end
trace.finalChannel = fft([weights.', zeros(1, N - tapCount)]);
end

function [bits, curve, trace] = iterate_fd_blms_turbo(Y, Hinitial, ...
        Hreference, noiseVariance, info, permutation, inversePermutation, ...
        cfg, useDecisionFeedback)
N = numel(Y);
weights = normalized_mmse(Hinitial, noiseVariance);
referenceWeights = normalized_mmse(Hreference, noiseVariance);
softSymbols = initial_soft_feedback(Y, Hinitial, noiseVariance, ...
    permutation, inversePermutation);
curve = zeros(1, cfg.iterations);
trace = initialize_trace(cfg.iterations, N, weights);
for iteration = 1:cfg.iterations
    if useDecisionFeedback
        feedback = weights .* Hinitial - 1;
    else
        feedback = zeros(size(weights));
    end
    estimate = ifft(weights .* Y - feedback .* fft(softSymbols));
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    [bits, decoderLlr, softSymbols] = decoder_feedback(equalizerLlr, ...
        permutation, inversePermutation, softSymbols, cfg);
    residual = softSymbols - estimate;
    errorSpectrum = fft(residual);
    weights = (1 - cfg.blmsLeakage) * weights + cfg.blmsStep * ...
        conj(Y) .* errorSpectrum ./ (abs(Y).^2 + cfg.blmsRegularization);
    weights = weights / max(real(mean(weights .* Hinitial)), eps);
    curve(iteration) = mean(bits ~= info);
    trace = save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, []);
    trace.frequencyWeights(iteration, :) = weights;
    trace.weightNmse(iteration) = channel_nmse(weights, referenceWeights);
    trace.errorPower(iteration) = mean(abs(residual).^2);
end
trace.finalChannel = weights;
end

function softSymbols = initial_soft_feedback(Y, Hinitial, noiseVariance, ...
        permutation, inversePermutation)
initialEstimate = ifft(normalized_mmse(Hinitial, noiseVariance) .* Y);
initialLlr = 2 * real(initialEstimate) / noiseVariance;
equalizerInput = initialLlr(inversePermutation);
[~, codedLlr] = bcjr_siso_decode(equalizerInput, "Log-MAP");
softSymbols = tanh(codedLlr(permutation) / 2);
end

function [bits, decoderLlr, softSymbols] = decoder_feedback(equalizerLlr, ...
        permutation, inversePermutation, previousSoftSymbols, cfg)
equalizerInput = equalizerLlr(inversePermutation);
[informationLlr, codedLlr] = bcjr_siso_decode( ...
    equalizerInput, "Log-MAP");
decoderExtrinsic = codedLlr - equalizerInput;
decoderLlr = decoderExtrinsic(permutation);
decoderPosterior = codedLlr(permutation);
candidate = tanh(decoderPosterior / 2);
softSymbols = (1 - cfg.turboDamping) * previousSoftSymbols + ...
    cfg.turboDamping * candidate;
bits = informationLlr < 0;
end

function trace = initialize_trace(iterations, blockLength, initialChannel)
trace.equalizerLlr = zeros(iterations, blockLength);
trace.decoderLlr = zeros(iterations, blockLength);
trace.reliability = zeros(1, iterations);
trace.channelNmse = nan(1, iterations);
trace.weightNmse = nan(1, iterations);
trace.errorPower = nan(1, iterations);
trace.frequencyWeights = complex(zeros(iterations, blockLength));
trace.initialChannel = initialChannel;
trace.finalChannel = initialChannel;
end

function trace = save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, channelNmse)
trace.equalizerLlr(iteration, :) = equalizerLlr;
trace.decoderLlr(iteration, :) = decoderLlr;
trace.reliability(iteration) = mean(abs(softSymbols).^2);
if ~isempty(channelNmse)
    trace.channelNmse(iteration) = channelNmse;
end
end

function [informationLlr, codedLlr, metric] = bcjr_siso_decode(codedLlr, mode)
mode = canonical_decoder_mode(mode);
if mode == "MAP"
    [informationLlr, codedLlr, metric] = bcjr_probability(codedLlr);
else
    [informationLlr, codedLlr, metric] = bcjr_log_domain(codedLlr, mode);
end
end

function [informationLlr, codedLlr, alpha] = bcjr_probability(codedLlr)
T = numel(codedLlr) / 2;
stateCount = 4;
[nextState, outputBits] = convolutional_trellis();
gamma = branch_metrics(codedLlr, nextState, outputBits, false);
alpha = zeros(T + 1, stateCount);
beta = zeros(T + 1, stateCount);
alpha(1, 1) = 1;
beta(T + 1, :) = 1 / stateCount;
for time = 1:T
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            alpha(time + 1, next) = alpha(time + 1, next) + ...
                alpha(time, state) * gamma(time, state, inputBit + 1);
        end
    end
    alpha(time + 1, :) = alpha(time + 1, :) / ...
        max(sum(alpha(time + 1, :)), realmin);
end
for time = T:-1:1
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            beta(time, state) = beta(time, state) + ...
                gamma(time, state, inputBit + 1) * beta(time + 1, next);
        end
    end
    beta(time, :) = beta(time, :) / max(sum(beta(time, :)), realmin);
end
[informationLlr, codedLlr] = probability_posteriors( ...
    alpha, beta, gamma, nextState, outputBits);
end

function [informationLlr, codedLlr, alpha] = bcjr_log_domain(codedLlr, mode)
T = numel(codedLlr) / 2;
stateCount = 4;
[nextState, outputBits] = convolutional_trellis();
gamma = branch_metrics(codedLlr, nextState, outputBits, true);
alpha = -inf(T + 1, stateCount);
beta = -inf(T + 1, stateCount);
alpha(1, 1) = 0;
beta(T + 1, :) = 0;
for time = 1:T
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            alpha(time + 1, next) = log_combine(alpha(time + 1, next), ...
                alpha(time, state) + gamma(time, state, inputBit + 1), mode);
        end
    end
    alpha(time + 1, :) = normalize_log_row(alpha(time + 1, :));
end
for time = T:-1:1
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            beta(time, state) = log_combine(beta(time, state), ...
                gamma(time, state, inputBit + 1) + beta(time + 1, next), mode);
        end
    end
    beta(time, :) = normalize_log_row(beta(time, :));
end
informationLlr = zeros(1, T);
codedLlr = zeros(1, 2 * T);
for time = 1:T
    inputValue = [-inf, -inf];
    codeValue = -inf(2, 2);
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            pathMetric = alpha(time, state) + ...
                gamma(time, state, inputBit + 1) + beta(time + 1, next);
            inputValue(inputBit + 1) = log_combine( ...
                inputValue(inputBit + 1), pathMetric, mode);
            bits = squeeze(outputBits(state, inputBit + 1, :)).';
            for codeIndex = 1:2
                codeValue(bits(codeIndex) + 1, codeIndex) = log_combine( ...
                    codeValue(bits(codeIndex) + 1, codeIndex), pathMetric, mode);
            end
        end
    end
    informationLlr(time) = inputValue(1) - inputValue(2);
    codedLlr(2 * time - 1) = codeValue(1, 1) - codeValue(2, 1);
    codedLlr(2 * time) = codeValue(1, 2) - codeValue(2, 2);
end
end

function gamma = branch_metrics(codedLlr, nextState, outputBits, logarithmic)
T = numel(codedLlr) / 2;
gamma = zeros(T, size(nextState, 1), 2);
for time = 1:T
    receivedLlr = codedLlr(2 * time - 1:2 * time);
    for state = 1:size(nextState, 1)
        for inputBit = 0:1
            bits = squeeze(outputBits(state, inputBit + 1, :)).';
            value = 0.5 * sum((1 - 2 * bits) .* receivedLlr);
            if logarithmic
                gamma(time, state, inputBit + 1) = value;
            else
                gamma(time, state, inputBit + 1) = exp(max(-50, min(50, value)));
            end
        end
    end
end
end

function [informationLlr, codedLlr] = probability_posteriors( ...
        alpha, beta, gamma, nextState, outputBits)
T = size(gamma, 1);
informationLlr = zeros(1, T);
codedLlr = zeros(1, 2 * T);
for time = 1:T
    inputValue = zeros(1, 2);
    codeValue = zeros(2, 2);
    for state = 1:size(nextState, 1)
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            pathMetric = alpha(time, state) * ...
                gamma(time, state, inputBit + 1) * beta(time + 1, next);
            inputValue(inputBit + 1) = inputValue(inputBit + 1) + pathMetric;
            bits = squeeze(outputBits(state, inputBit + 1, :)).';
            for codeIndex = 1:2
                codeValue(bits(codeIndex) + 1, codeIndex) = ...
                    codeValue(bits(codeIndex) + 1, codeIndex) + pathMetric;
            end
        end
    end
    informationLlr(time) = log(max(inputValue(1), realmin)) - ...
        log(max(inputValue(2), realmin));
    codedLlr(2 * time - 1) = log(max(codeValue(1, 1), realmin)) - ...
        log(max(codeValue(2, 1), realmin));
    codedLlr(2 * time) = log(max(codeValue(1, 2), realmin)) - ...
        log(max(codeValue(2, 2), realmin));
end
end

function row = normalize_log_row(row)
maximum = max(row);
if isfinite(maximum)
    row = row - maximum;
end
end

function value = log_combine(left, right, mode)
if mode == "Max-Log-MAP"
    value = max(left, right);
    return;
end
maximum = max(left, right);
if isinf(maximum)
    value = maximum;
else
    value = maximum + log(exp(left - maximum) + exp(right - maximum));
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

function coded = convolutional_encode(bits)
state = [0, 0];
coded = zeros(1, 2 * numel(bits));
for index = 1:numel(bits)
    inputBit = bits(index);
    coded(2 * index - 1) = mod(inputBit + state(2), 2);
    coded(2 * index) = mod(inputBit + state(1) + state(2), 2);
    state = [inputBit, state(1)];
end
end

function matrix = circulant_channel(channel, blockLength)
column = [channel(:); zeros(blockLength - numel(channel), 1)];
matrix = zeros(blockLength);
for index = 1:blockLength
    matrix(:, index) = circshift(column, index - 1);
end
end

function weights = normalized_mmse(H, noiseVariance)
weights = conj(H) ./ (abs(H).^2 + noiseVariance);
weights = weights / max(real(mean(weights .* H)), eps);
end

function decisions = hard_bpsk(values)
decisions = 1 - 2 * (real(values) < 0);
end

function nmse = channel_nmse(estimate, reference)
nmse = sum(abs(estimate - reference).^2) / ...
    max(sum(abs(reference).^2), eps);
end

function path = plot_results(result)
path = fullfile(result.config.outputDir, "chapter4_iterative_equalization.png");
if ~exist(fileparts(path), "dir")
    mkdir(fileparts(path));
end
fig = figure("Color", "w", "Position", [80, 80, 1440, 860], ...
    "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
markers = ["o-", "s-", "^-", "d-", "v-", ">-", "<-", "p-", "h-", ...
    "x-", "+-", "*-"];
plotFloor = 1e-5;
nexttile; hold on;
for index = 1:numel(result.methodNames)
    semilogy(result.snrList, max(result.ber(index, :), plotFloor), ...
        markers(index), "LineWidth", 1.2);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("信息比特误码率 BER");
title("第 4 章已选迭代均衡算法");
legend(result.methodNames, "Location", "southwest");

nexttile; hold on;
for index = 1:numel(result.methodNames)
    plot(1:result.config.iterations, result.methodIterationBer(index, :), ...
        markers(index), "LineWidth", 1.1);
end
grid on; xlabel("Turbo 迭代次数"); ylabel("信息比特错误率");
title("单帧迭代收敛过程");
legend(result.methodNames, "Location", "northeast");

nexttile; hold on;
for index = 1:numel(result.decoderNames)
    semilogy(result.snrList, max(result.decoderBer(index, :), plotFloor), ...
        markers(index), "LineWidth", 1.2);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("信息比特误码率 BER");
title("MAP、Log-MAP 与 Max-Log-MAP 译码对比");
legend(result.decoderNames, "Location", "southwest");

nexttile;
blmsIndex = find(strcmp(result.availableMethods, "BLMS-TF-Turbo"), 1);
channelTrace = result.example.methodTraces{blmsIndex};
plot(1:result.config.iterations, channelTrace.channelNmse, "o-", ...
    "LineWidth", 1.3); hold on;
plot(1:result.config.iterations, channelTrace.reliability, "s-", ...
    "LineWidth", 1.3);
grid on; xlabel("Turbo 迭代次数"); ylabel("数值");
title("BLMS 时频 Turbo 的信道更新与软可靠度");
legend("信道估计 NMSE", "软符号可靠度", "Location", "best");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function path = plot_turbo_exchange(result)
path = fullfile(result.config.outputDir, "chapter4_turbo_soft_information.png");
if ~exist(fileparts(path), "dir")
    mkdir(fileparts(path));
end
traceIndex = find(contains(result.methodNames, "Turbo"), 1);
if isempty(traceIndex)
    traceIndex = 1;
end
trace = result.methodTraces{traceIndex};
showCount = min(72, size(trace.equalizerLlr, 2));
fig = figure("Color", "w", "Position", [100, 100, 1380, 760], ...
    "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
nexttile;
plot(trace.equalizerLlr(1, 1:showCount), "LineWidth", 1.0); hold on;
plot(trace.decoderLlr(1, 1:showCount), "LineWidth", 1.0);
grid on; xlabel("编码位索引"); ylabel("LLR");
title("第 1 次迭代：均衡器与译码器软信息");
legend("均衡器输出 LLR", "译码器后验 LLR", "Location", "best");

nexttile;
plot(trace.equalizerLlr(end, 1:showCount), "LineWidth", 1.0); hold on;
plot(trace.decoderLlr(end, 1:showCount), "LineWidth", 1.0);
grid on; xlabel("编码位索引"); ylabel("LLR");
title("最后一次迭代：软信息交换结果");
legend("均衡器输出 LLR", "译码器后验 LLR", "Location", "best");

nexttile;
plot(1:numel(trace.reliability), trace.reliability, "o-", "LineWidth", 1.3);
grid on; ylim([0, 1]); xlabel("Turbo 迭代次数"); ylabel("软符号可靠度");
title("译码反馈的可信度");

nexttile;
histogram(trace.decoderLlr(end, :), 24, "Normalization", "probability");
grid on; xlabel("最后一次译码器后验 LLR"); ylabel("概率");
title("编码位软信息分布");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
end

function path = plot_frequency_adaptive_blms(result)
adaptiveNames = ["TDDA-TEQ", "FDDA-TEQ", "FDDA-DFE-TEQ"];
selected = find(ismember(result.methodNames, adaptiveNames));
if isempty(selected)
    path = "";
    return;
end
path = fullfile(result.config.outputDir, ...
    "chapter4_blms_frequency_adaptive_turbo.png");
if ~exist(fileparts(path), "dir")
    mkdir(fileparts(path));
end
fig = figure("Color", "w", "Position", [110, 110, 1420, 820], ...
    "Visible", "off");
tiledlayout(2, 2, "TileSpacing", "compact", "Padding", "compact");
markers = ["o-", "s-", "^-", "d-", "v-"];
plotFloor = 1e-5;
nexttile; hold on;
for index = 1:numel(selected)
    methodIndex = selected(index);
    semilogy(result.snrList, max(result.ber(methodIndex, :), plotFloor), ...
        markers(index), "LineWidth", 1.3);
end
grid on; xlabel("信噪比 SNR (dB)"); ylabel("信息比特误码率 BER");
title("基于 BLMS 的自适应 Turbo 均衡性能");
legend(result.methodNames(selected), "Location", "southwest");

nexttile; hold on;
for index = 1:numel(selected)
    methodIndex = selected(index);
    plot(1:result.config.iterations, ...
        result.methodIterationBer(methodIndex, :), markers(index), ...
        "LineWidth", 1.3);
end
grid on; xlabel("Turbo 迭代次数"); ylabel("信息比特错误率");
title("自适应分支的单帧收敛");
legend(result.methodNames(selected), "Location", "northeast");

nexttile; hold on;
for index = 1:numel(selected)
    trace = result.methodTraces{selected(index)};
    plot(abs(trace.frequencyWeights(end, :)), markers(index), ...
        "LineWidth", 1.0, "MarkerIndices", ...
        1:8:size(trace.frequencyWeights, 2));
end
grid on; xlabel("频域抽头索引"); ylabel("最终前馈权重幅度");
title("BLMS 频域自适应前馈系数");
legend(result.methodNames(selected), "Location", "best");

nexttile; hold on;
for index = 1:numel(selected)
    trace = result.methodTraces{selected(index)};
    semilogy(1:result.config.iterations, ...
        max(trace.errorPower, plotFloor), markers(index), "LineWidth", 1.3);
end
grid on; xlabel("Turbo 迭代次数"); ylabel("块均方残差");
title("BLMS 判决导向块残差");
legend(result.methodNames(selected), "Location", "best");
set(findall(fig, "Type", "axes"), "FontName", "Microsoft YaHei");
exportgraphics(fig, path, "Resolution", 180);
close(fig);
path = string(path);
end

function [selected, requested] = select_method_indices(available, requested, label)
requested = string(requested);
if isscalar(requested) && strcmpi(requested, "all")
    selected = 1:numel(available);
    requested = available;
    return;
end
selected = zeros(1, numel(requested));
for index = 1:numel(requested)
    canonical = canonical_method_id(requested(index));
    match = find(strcmpi(canonical, available), 1);
    assert(~isempty(match), "SCFDE:UnknownMethod", ...
        "Unknown %s method: %s. Available: %s", label, requested(index), ...
        strjoin(available, ", "));
    selected(index) = match;
end
assert(numel(unique(selected)) == numel(selected), ...
    "SCFDE:DuplicateMethod", "A %s method was selected twice.", label);
end

function id = canonical_method_id(id)
id = string(id);
switch lower(id)
    case "time turbo"
        id = "TD-Turbo-Log-MAP";
    case "frequency dfe"
        id = "FD-DFE";
    case "tf turbo"
        id = "TF-Turbo-Log-MAP";
    case "bidirectional tf"
        id = "BiTF-Turbo-Log-MAP";
    case "blms tf turbo"
        id = "BLMS-TF-Turbo";
end
end

function mode = canonical_decoder_mode(mode)
mode = string(mode);
switch lower(mode)
    case "map"
        mode = "MAP";
    case {"logmap", "log-map"}
        mode = "Log-MAP";
    case {"maxlog", "max-log-map", "maxlogmap"}
        mode = "Max-Log-MAP";
    otherwise
        error("SCFDE:UnknownDecoder", ...
            "Unknown BCJR decoder mode: %s", mode);
end
end

function output = merge_options(defaults, options)
output = defaults;
names = fieldnames(options);
for index = 1:numel(names)
    output.(names{index}) = options.(names{index});
end
end
