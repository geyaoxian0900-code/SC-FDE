function [bits, curve, trace] = ch4_iterate_time_turbo(received, channelMatrix, ...
        timeEqualizer, noiseVariance, frame, cfg, decoderMode)
%CH4_ITERATE_TIME_TURBO Time-domain turbo equalization on the validated
% Chapter-4 frame contract.  The equalizer operates on the full
% [training; coded-data] frame; BCJR sees ONLY the coded-data LLRs
% (ch4_decoder_feedback_frame) and returns exactly 512 information
% bits; the feedback frame is rebuilt in transmitted order with the
% training positions locked to the known training symbols.
N = frame.frameLength;
softSymbols = zeros(1, N);
softSymbols(frame.trainingIndices) = frame.trainingSymbols;
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, []);
for iteration = 1:cfg.iterations
    estimate = softSymbols + (timeEqualizer * ...
        (received(:) - channelMatrix * softSymbols(:))).';
    equalizerLlr = 2 * real(estimate)/noiseVariance;
    [bits, decoderLlr, softSymbols] = ...
        scfde.equalizers.ch4_decoder_feedback_frame( ...
            equalizerLlr, frame, softSymbols, cfg.turboDamping, decoderMode);
    curve(iteration) = mean(bits ~= frame.informationBits);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, []);
end
trace.finalChannel = [];
end
