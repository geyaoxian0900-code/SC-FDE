function [bits, curve, trace] = ch4_iterate_time_frequency_turbo(received, Y, ...
        channelMatrix, timeEqualizer, Hest, Hreference, noiseVariance, ...
        info, permutation, inversePermutation, cfg, bidirectional, adaptiveChannel)
N = numel(received);
softSymbols = zeros(1, N);
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, Hest);
if bidirectional
    reverseChannel = rot90(channelMatrix, 2);
    reverseEqualizer = (reverseChannel' * reverseChannel + ...
        noiseVariance * eye(N)) \ reverseChannel';
end
for iteration = 1:cfg.iterations
    timeEstimate = softSymbols.' + timeEqualizer * ...
        (received(:) - channelMatrix * softSymbols.');
    rho = min(0.995, mean(abs(softSymbols).^2));
    [feedforward, feedback] = scfde.equalizers.ch4_fd_ibdfe_weights(Hest, noiseVariance, rho);
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
    [informationLlr, codedLlr] = scfde.equalizers.ch4_bcjr_siso_decode( ...
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
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, scfde.equalizers.ch4_channel_nmse(Hest, Hreference));
end
trace.finalChannel = Hest;
end