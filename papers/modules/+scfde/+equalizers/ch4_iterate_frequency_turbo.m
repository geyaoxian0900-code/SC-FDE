function [bits, curve, trace] = ch4_iterate_frequency_turbo(Y, Hest, ...
        Hreference, noiseVariance, info, permutation, inversePermutation, ...
        cfg, decoderMode, adaptiveChannel)
N = numel(Y);
softSymbols = zeros(1, N);
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, Hest);
for iteration = 1:cfg.iterations
    rho = min(0.995, mean(abs(softSymbols).^2));
    [feedforward, feedback] = scfde.equalizers.ch4_fd_ibdfe_weights(Hest, noiseVariance, rho);
    estimate = ifft(feedforward .* Y - feedback .* fft(softSymbols));
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    equalizerInput = equalizerLlr(inversePermutation);
    [informationLlr, codedLlr] = scfde.equalizers.ch4_bcjr_siso_decode( ...
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
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, scfde.equalizers.ch4_channel_nmse(Hest, Hreference));
end
trace.finalChannel = Hest;
end