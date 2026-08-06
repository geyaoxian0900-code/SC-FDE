function [bits, curve, trace] = ch4_iterate_time_turbo(received, channelMatrix, ...
        timeEqualizer, noiseVariance, info, permutation, inversePermutation, ...
        cfg, decoderMode)
N = numel(received);
softSymbols = zeros(N, 1);
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, []);
for iteration = 1:cfg.iterations
    estimate = softSymbols + timeEqualizer * ...
        (received(:) - channelMatrix * softSymbols);
    equalizerLlr = 2 * real(estimate).'/noiseVariance;
    equalizerInput = equalizerLlr(inversePermutation);
    [informationLlr, codedLlr] = scfde.equalizers.ch4_bcjr_siso_decode( ...
        equalizerInput, decoderMode);
    decoderExtrinsic = codedLlr - equalizerInput;
    decoderLlr = decoderExtrinsic(permutation);
    decoderPosterior = codedLlr(permutation);
    candidate = tanh(decoderPosterior / 2).';
    softSymbols = (1 - cfg.turboDamping) * softSymbols + ...
        cfg.turboDamping * candidate;
    bits = informationLlr < 0;
    curve(iteration) = mean(bits ~= info);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, []);
end
trace.finalChannel = [];
end