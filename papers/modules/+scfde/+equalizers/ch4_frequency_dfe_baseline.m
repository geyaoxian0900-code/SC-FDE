function [bits, curve, trace] = ch4_frequency_dfe_baseline(Y, H, ...
        noiseVariance, frame, cfg)
%CH4_FREQUENCY_DFE_BASELINE Frequency-domain DFE on the validated
% Chapter-4 frame contract.  The DFE equalizes the full frame; the
% BCJR input is limited to the 1024 coded-data positions
% (ch4_decoder_feedback_frame) and returns exactly 512 information
% bits.  The decoder is applied once; its trace values are repeated
% for the configured iterations.
N = frame.frameLength;
feedforward = scfde.equalizers.ch4_normalized_mmse(H, noiseVariance);
linearEstimate = ifft(feedforward .* Y);
initialDecision = scfde.equalizers.ch4_hard_bpsk(linearEstimate);
feedback = feedforward .* H - 1;
estimate = ifft(feedforward .* Y - feedback .* fft(initialDecision));
equalizerLlr = 2 * real(estimate) / noiseVariance;
previous = zeros(1, N);
previous(frame.trainingIndices) = frame.trainingSymbols;
[bits, decoderLlr, softFrame] = ...
    scfde.equalizers.ch4_decoder_feedback_frame( ...
        equalizerLlr, frame, previous, 1, cfg.baselineDecoder);
curve = mean(bits ~= frame.informationBits) * ones(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, []);
for iteration = 1:cfg.iterations
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softFrame, []);
end
trace.finalChannel = H;
end
