function [bits, curve, trace] = ch4_frequency_dfe_baseline(Y, H, ...
        noiseVariance, info, inversePermutation, cfg)
N = numel(Y);
feedforward = scfde.equalizers.ch4_normalized_mmse(H, noiseVariance);
linearEstimate = ifft(feedforward .* Y);
initialDecision = scfde.equalizers.ch4_hard_bpsk(linearEstimate);
feedback = feedforward .* H - 1;
estimate = ifft(feedforward .* Y - feedback .* fft(initialDecision));
equalizerLlr = 2 * real(estimate) / noiseVariance;
[informationLlr, codedLlr] = scfde.equalizers.ch4_bcjr_siso_decode( ...
    equalizerLlr(inversePermutation), cfg.baselineDecoder);
bits = informationLlr < 0;
curve = mean(bits ~= info) * ones(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, []);
for iteration = 1:cfg.iterations
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, codedLlr, ...
        tanh(codedLlr / 2).', []);
end
trace.finalChannel = H;
end