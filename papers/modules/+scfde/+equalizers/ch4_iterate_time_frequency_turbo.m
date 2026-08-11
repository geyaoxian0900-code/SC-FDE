function [bits, curve, trace] = ch4_iterate_time_frequency_turbo(received, Y, ...
        channelMatrix, timeEqualizer, Hest, Hreference, noiseVariance, ...
        frame, cfg, bidirectional, adaptiveChannel)
%CH4_ITERATE_TIME_FREQUENCY_TURBO Time-frequency turbo equalization on
% the validated Chapter-4 frame contract.  Full-frame soft symbols
% (training locked to known symbols) drive the time and frequency
% equalizers; BCJR sees ONLY the coded-data LLRs and returns exactly
% 512 information bits; the feedback frame is rebuilt in transmitted
% order.
N = frame.frameLength;
softSymbols = zeros(1, N);
softSymbols(frame.trainingIndices) = frame.trainingSymbols;
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, Hest);
if bidirectional
    reverseChannel = rot90(channelMatrix, 2);
    reverseEqualizer = (reverseChannel' * reverseChannel + ...
        noiseVariance * eye(N)) \ reverseChannel';
end
for iteration = 1:cfg.iterations
    timeEstimate = softSymbols + (timeEqualizer * ...
        (received(:) - channelMatrix * softSymbols(:))).';
    rho = min(0.995, mean(abs(softSymbols).^2));
    [feedforward, feedback] = scfde.equalizers.ch4_fd_ibdfe_weights(Hest, noiseVariance, rho);
    frequencyEstimate = ifft(feedforward .* Y - feedback .* fft(softSymbols));
    estimate = 0.5 * timeEstimate + 0.5 * frequencyEstimate;
    if bidirectional
        reverseSoft = fliplr(softSymbols);
        reverseReceived = flipud(received(:));
        reverseEstimate = reverseSoft + (reverseEqualizer * ...
            (reverseReceived - reverseChannel * reverseSoft(:))).';
        estimate = 0.5 * estimate + 0.5 * fliplr(reverseEstimate);
    end
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    [bits, decoderLlr, softSymbols] = ...
        scfde.equalizers.ch4_decoder_feedback_frame( ...
            equalizerLlr, frame, softSymbols, cfg.turboDamping, "Log-MAP");
    if adaptiveChannel
        softSpectrum = fft(softSymbols);
        innovation = Y - Hest .* softSpectrum;
        Hest = Hest + cfg.blmsStep * conj(softSpectrum) .* innovation ./ ...
            (abs(softSpectrum).^2 + noiseVariance * N);
    end
    curve(iteration) = mean(bits ~= frame.informationBits);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, scfde.equalizers.ch4_channel_nmse(Hest, Hreference));
    trace.softEstimates(iteration, :) = estimate;
end
trace.finalChannel = Hest;
end
