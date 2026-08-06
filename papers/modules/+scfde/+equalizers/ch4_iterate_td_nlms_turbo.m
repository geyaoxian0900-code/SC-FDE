function [bits, curve, trace] = ch4_iterate_td_nlms_turbo(received, Y, ...
        Hinitial, Hreference, noiseVariance, info, permutation, ...
        inversePermutation, cfg)
N = numel(received);
tapCount = min(cfg.tdAdaptiveTaps, N);
initialImpulse = ifft(scfde.equalizers.ch4_normalized_mmse(Hinitial, noiseVariance));
weights = initialImpulse(1:tapCount).';
referenceWeights = scfde.equalizers.ch4_normalized_mmse(Hreference, noiseVariance);
softSymbols = scfde.equalizers.ch4_initial_soft_feedback(Y, Hinitial, noiseVariance, ...
    permutation, inversePermutation);
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, []);
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
    [bits, decoderLlr, softSymbols] = scfde.equalizers.ch4_decoder_feedback(equalizerLlr, ...
        permutation, inversePermutation, softSymbols, cfg);
    weightSpectrum = fft([weights.', zeros(1, N - tapCount)]);
    curve(iteration) = mean(bits ~= info);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, []);
    trace.frequencyWeights(iteration, :) = weightSpectrum;
    trace.weightNmse(iteration) = scfde.equalizers.ch4_channel_nmse(weightSpectrum, referenceWeights);
    trace.errorPower(iteration) = mean(abs(residual).^2);
end
trace.finalChannel = fft([weights.', zeros(1, N - tapCount)]);
end