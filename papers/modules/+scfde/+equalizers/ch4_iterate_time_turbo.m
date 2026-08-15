function [bits, curve, trace] = ch4_iterate_time_turbo(received, channelMatrix, ...
        timeEqualizer, noiseVariance, frame, cfg, decoderMode) %#ok<INUSD>
%CH4_ITERATE_TIME_TURBO Time-domain turbo equalization on the validated
% Chapter-4 frame contract.  Strict spec-4.1 boxed per-iteration LMMSE:
%     V = diag(v_k),  v_k = 1 - |x_bar_k|^2  (BPSK decoder soft means)
%     x_hat = x_bar + V H^H (H V H^H + sigma_w^2 I)^{-1} (y - H x_bar)
% (the previous fixed-filter residual form is replaced; TIMEEQUALIZER is
% kept in the signature for compatibility and ignored).  BCJR sees ONLY
% the coded-data LLRs (ch4_decoder_feedback_frame) and returns exactly
% 512 information bits; the feedback frame is rebuilt in transmitted
% order with the training positions locked to the known symbols.
N = frame.frameLength;
softSymbols = zeros(1, N);
softSymbols(frame.trainingIndices) = frame.trainingSymbols;
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, []);
for iteration = 1:cfg.iterations
    % (4-24)~(4-31): per-symbol variances from the decoder soft means.
    symbolVariance = max(1 - abs(softSymbols).^2, 1e-6);
    V = diag(symbolVariance);
    residual = received(:) - channelMatrix * softSymbols(:);
    correction = V * (channelMatrix' * ((channelMatrix * V * ...
        channelMatrix' + noiseVariance * eye(N)) \ residual));
    estimate = softSymbols + correction.';
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    [bits, decoderLlr, softSymbols] = ...
        scfde.equalizers.ch4_decoder_feedback_frame( ...
            equalizerLlr, frame, softSymbols, 1, decoderMode);
    curve(iteration) = mean(bits ~= frame.informationBits);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, []);
    trace.softEstimates(iteration, :) = estimate;
end
trace.finalChannel = [];
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = struct("iterations", cfg.iterations, ...
    "decoderMode", string(decoderMode), ...
    "noiseVariance", noiseVariance, "frameLength", N);
trace.formulaNote = "(4-24)~(4-31) per-iteration LMMSE: x_hat = x_bar + V H^H (H V H^H + sigma_w^2 I)^{-1} (y - H x_bar), V = diag(1-|x_bar|^2); extrinsic LLR generation ALG-EQUIV (Gaussian model with mu=1, sigma^2=sigma_w^2)";
trace.dampingStatus = "BOOK path undamped (damping=1); cfg.turboDamping reserved (engineering)";
end
