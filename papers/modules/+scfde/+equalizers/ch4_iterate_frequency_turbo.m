function [bits, curve, trace] = ch4_iterate_frequency_turbo(Y, Hest, ...
        Hreference, noiseVariance, frame, cfg, decoderMode, adaptiveChannel)
%CH4_ITERATE_FREQUENCY_TURBO Frequency-domain turbo equalization on the
% validated Chapter-4 frame contract (spec 4.3).
%   X_hat^(i) = F^{-1}[ W^(i) Y - B^(i) F x_bar^(i-1) ],
%   x_bar^(i) = E[x | L_D^{e,(i-1)}]  (decoder EXTRINSIC soft means).
%   The equivalent gain and residual variance follow (4-60)/(4-61),
%   estimated over the TRAINING segment where the true symbols are
%   known:  mu_hat = (1/Lt) sum x_hat_k x_k*,
%           sigma_hat^2 = (1/Lt) sum |x_hat_k - mu_hat x_k|^2,
%   and the extrinsic LLRs follow (4-42)/(4-43):
%       L^E = ln sum_{s in S^0} p(x_tilde|s) prod P(c) / sum_{s in S^1} ...
%   which for BPSK reduces to 2 Re{mu_hat* x_tilde}/sigma_hat^2.
%   Equalizer and BCJR exchange ONLY extrinsic information (the decoder
%   feedback mean is built from L_D^e inside ch4_decoder_feedback_frame).
%   The BOOK path is undamped (damping=1); cfg.turboDamping is reserved.
%   (4-57)/(4-58) numerator/denominator of the W/B coefficients remain
%   BLOCKED-SOURCE-REVIEW pending book/21.png; the current
%   ch4_fd_ibdfe_weights construction is kept with the zero-mean
%   constraint enforced (spec 4.2).
N = frame.frameLength;
softSymbols = zeros(1, N);
softSymbols(frame.trainingIndices) = frame.trainingSymbols;
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, Hest);
trainingX = frame.trainingSymbols(:).';
trainingX = trainingX(1:numel(frame.trainingIndices));
for iteration = 1:cfg.iterations
    rho = min(0.995, mean(abs(softSymbols).^2));
    [feedforward, feedback] = scfde.equalizers.ch4_fd_ibdfe_weights(Hest, noiseVariance, rho);
    estimate = ifft(feedforward .* Y - feedback .* fft(softSymbols));
    % (4-60)/(4-61) over the training segment (true symbols known).
    muHat = mean(estimate(frame.trainingIndices) .* conj(trainingX));
    sigmaHat2 = max(mean(abs(estimate(frame.trainingIndices) - ...
        muHat * trainingX).^2), noiseVariance);
    equalizerLlr = zeros(1, N);
    equalizerLlr(frame.dataIndices) = 2 * real(conj(muHat) * ...
        estimate(frame.dataIndices)) / sigmaHat2;
    [bits, decoderLlr, softSymbols] = ...
        scfde.equalizers.ch4_decoder_feedback_frame( ...
            equalizerLlr, frame, softSymbols, 1, decoderMode);
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
    trace.equivalentGain(iteration) = muHat;
    trace.residualVariance(iteration) = sigmaHat2;
end
trace.finalChannel = Hest;
trace.formulaStatus = "BLOCKED-SOURCE-REVIEW";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = struct("iterations", cfg.iterations, ...
    "decoderMode", string(decoderMode), ...
    "noiseVariance", noiseVariance, "frameLength", N, ...
    "adaptiveChannel", logical(adaptiveChannel));
trace.formulaNote = "(4-42)/(4-43)/(4-50)/(4-60)/(4-61): FD-IBDFE with decoder-extrinsic soft feedback, mu/sigma^2 from the training segment, extrinsic-only exchange, undamped; the IBDFE coefficient form (4-57)/(4-58) is still BLOCKED-SOURCE-REVIEW (book/21.png), so the method as a whole is NOT certified BOOK-EXACT";
end
