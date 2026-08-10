function softFrame = ch4_initial_soft_feedback(Y, Hinitial, ...
        noiseVariance, frame, cfg)
%CH4_INITIAL_SOFT_FEEDBACK Frame-aware initial soft feedback: the MMSE
% estimate LLR covers the full frame; BCJR sees only the coded-data
% LLRs; the returned soft frame is in transmitted order with the
% training positions locked to the known training symbols.
initialEstimate = ifft( ...
    scfde.equalizers.ch4_normalized_mmse(Hinitial, noiseVariance) .* Y);
initialLlr = 2 * real(initialEstimate) / noiseVariance;
previous = zeros(1, frame.frameLength);
previous(frame.trainingIndices) = frame.trainingSymbols;
[~, ~, softFrame] = scfde.equalizers.ch4_decoder_feedback_frame( ...
    initialLlr, frame, previous, cfg.turboDamping, "Log-MAP");
end
