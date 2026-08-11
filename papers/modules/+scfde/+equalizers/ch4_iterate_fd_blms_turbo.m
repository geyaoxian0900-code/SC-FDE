function [bits, curve, trace] = ch4_iterate_fd_blms_turbo(Y, Hinitial, ...
        Hreference, noiseVariance, frame, cfg, useDecisionFeedback)
%CH4_ITERATE_FD_BLMS_TURBO FD-BLMS direct-adaptive turbo equalization on
% the validated Chapter-4 frame contract.  The residual is the
% full-frame softSymbols - estimate (length 1280); BCJR sees only the
% coded-data LLRs and returns exactly 512 information bits.
N = frame.frameLength;
weights = scfde.equalizers.ch4_normalized_mmse(Hinitial, noiseVariance);
referenceWeights = scfde.equalizers.ch4_normalized_mmse(Hreference, noiseVariance);
softSymbols = scfde.equalizers.ch4_initial_soft_feedback(Y, Hinitial, ...
    noiseVariance, frame, cfg);
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, weights);
for iteration = 1:cfg.iterations
    if useDecisionFeedback
        feedback = weights .* Hinitial - 1;
    else
        feedback = zeros(size(weights));
    end
    estimate = ifft(weights .* Y - feedback .* fft(softSymbols));
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    [bits, decoderLlr, softSymbols] = ...
        scfde.equalizers.ch4_decoder_feedback_frame( ...
            equalizerLlr, frame, softSymbols, cfg.turboDamping, "Log-MAP");
    residual = softSymbols - estimate;
    errorSpectrum = fft(residual);
    weights = (1 - cfg.blmsLeakage) * weights + cfg.blmsStep * ...
        conj(Y) .* errorSpectrum ./ (abs(Y).^2 + cfg.blmsRegularization);
    weights = weights / max(real(mean(weights .* Hinitial)), eps);
    curve(iteration) = mean(bits ~= frame.informationBits);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, []);
    trace.softEstimates(iteration, :) = estimate;
    trace.frequencyWeights(iteration, :) = weights;
    trace.weightNmse(iteration) = scfde.equalizers.ch4_channel_nmse(weights, referenceWeights);
    trace.errorPower(iteration) = mean(abs(residual).^2);
end
trace.finalChannel = weights;
end
