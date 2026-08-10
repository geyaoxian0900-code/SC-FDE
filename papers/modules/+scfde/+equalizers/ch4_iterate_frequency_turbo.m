function [bits, curve, trace] = ch4_iterate_frequency_turbo(Y, Hest, ...
        Hreference, noiseVariance, frame, cfg, decoderMode, adaptiveChannel)
%CH4_ITERATE_FREQUENCY_TURBO Frequency-domain turbo equalization on the
% validated Chapter-4 frame contract.  The full-frame soft symbols
% (training locked to the known symbols) feed the IBDFE; BCJR sees
% ONLY the coded-data LLRs and returns exactly 512 information bits;
% the feedback frame is rebuilt in transmitted order.
N = frame.frameLength;
softSymbols = zeros(1, N);
softSymbols(frame.trainingIndices) = frame.trainingSymbols;
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, Hest);
for iteration = 1:cfg.iterations
    rho = min(0.995, mean(abs(softSymbols).^2));
    [feedforward, feedback] = scfde.equalizers.ch4_fd_ibdfe_weights(Hest, noiseVariance, rho);
    estimate = ifft(feedforward .* Y - feedback .* fft(softSymbols));
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    [bits, decoderLlr, softSymbols] = ...
        scfde.equalizers.ch4_decoder_feedback_frame( ...
            equalizerLlr, frame, softSymbols, cfg.turboDamping, decoderMode);
    if adaptiveChannel
        softSpectrum = fft(softSymbols);
        innovation = Y - Hest .* softSpectrum;
        Hest = Hest + cfg.blmsStep * conj(softSpectrum) .* innovation ./ ...
            (abs(softSpectrum).^2 + noiseVariance * N);
    end
    curve(iteration) = mean(bits ~= frame.informationBits);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, scfde.equalizers.ch4_channel_nmse(Hest, Hreference));
end
trace.finalChannel = Hest;
end
