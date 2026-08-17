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
%   The W/B coefficients follow (4-56)~(4-58) recovered from
%   book/P90.png (ch4_fd_dfe_weights): D_k = sigma^2 + (1-rho)|h_k|^2,
%   lambda per (4-58) (imposes sum_k b_k = 0 algebraically, asserted
%   never projected), b_k per (4-57), w_k per (4-56); rho =
%   mean(|x_bar|^2) per (4-55) with NO empirical cap.  Method-level
%   BOOK-EXACT promotion is deferred to the Task 9 re-certification.
N = frame.frameLength;
softSymbols = zeros(1, N);
softSymbols(frame.trainingIndices) = frame.trainingSymbols;
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, Hest);
trace.rhoHistory = zeros(1, cfg.iterations);
trace.lambdaHistory = zeros(1, cfg.iterations);
trace.feedbackWeights = complex(zeros(cfg.iterations, N));
trainingX = frame.trainingSymbols(:).';
trainingX = trainingX(1:numel(frame.trainingIndices));
for iteration = 1:cfg.iterations
    rho = mean(abs(softSymbols).^2);      % (4-55), no empirical cap
    [feedforward, feedback, lambda] = ...
        scfde.equalizers.ch4_fd_dfe_weights(Hest, rho, noiseVariance);
    trace.rhoHistory(iteration) = rho;
    trace.lambdaHistory(iteration) = lambda;
    trace.frequencyWeights(iteration, :) = feedforward;
    trace.feedbackWeights(iteration, :) = feedback;
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
trace.formulaStatus = "ALG-EQUIV";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.sourcePages = "book/P90.png";
trace.sourceEquations = "(4-42)/(4-43)/(4-50)/(4-55)~(4-58)/(4-60)/(4-61)";
trace.effectiveParameters = struct("iterations", cfg.iterations, ...
    "decoderMode", string(decoderMode), ...
    "noiseVariance", noiseVariance, "frameLength", N, ...
    "adaptiveChannel", logical(adaptiveChannel));
trace.formulaNote = "(4-42)/(4-43)/(4-50)/(4-55)~(4-58)/(4-60)/(4-61): FD-Turbo with decoder-extrinsic soft feedback; W/B from the strict (4-56)~(4-58) coefficients (book/P90.png, ch4_fd_dfe_weights, zero-sum asserted not projected); rho = mean(|x_bar|^2) uncapped per (4-55); mu/sigma^2 from the training segment per (4-60)/(4-61); extrinsic-only exchange, undamped; ALG-EQUIV because the training-segment mu/sigma^2 estimator is an engineering placement of (4-60)/(4-61) (the book defines the quantities, not this estimator)";
end
