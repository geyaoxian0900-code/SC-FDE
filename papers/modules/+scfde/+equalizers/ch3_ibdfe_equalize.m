function [symbols, trace, H] = ch3_ibdfe_equalize(receivedData, ...
        receivedTraining, training, H, noiseVariance, uw, cfg, ...
        feedbackMode, updateChannel) %#ok<INUSD>
%CH3_IBDFE_EQUALIZE Strict IBDFE core (book (3-64)~(3-71), (3-84)~(3-92);
% spec 3.4~3.7).
%   RECEIVEDTRAINING and TRAINING remain in the shared interface (the
%   historical training-LS channel path); the strict (3-88)~(3-92)
%   data-driven channel update no longer uses them.
%   Iteration i:
%     X_hat^(i) = C^(i) .* R  -  B^(i) .* X_bar^(i-1)
%     C_k = A_k / Gamma,   B_k = C_k H_k - 1,   Gamma = mean(A .* H),
%     unit gain mean(C .* H) = 1 (asserted; spec 3.4).
%   Iteration 1 has zero feedback and degrades to MMSE-FDE (spec 3.4).
%   feedbackMode "soft": X_bar = E[x | L_a] (QPSK posterior mean, NO
%     hard slicing, spec 3.4); "hard": X_bar = Q{F^{-1} X_hat} from the
%     PREVIOUS complete block (spec 3.5).
%   updateChannel (spec 3.6/3.7, iterations >= 2 only - the first round
%   keeps the training-based H):
%     (3-88)/(3-89) H_LS = R ./ X_bar  (LS from the current soft/hard
%       symbol estimates);
%     (3-90)/(3-91) h_est = F^{-1}{H_LS}, DFT truncation to
%       channelEstimateLength taps -> H_DFT;
%     (3-92) boxed MMSE variance-weighted mix
%       H^(i) = (H^(i-1) sigma_DFT^2 + H_DFT^(i) sigma_old^2) /
%               (sigma_old^2 + sigma_DFT^2)
%     with the variance definitions sigma_DFT^2 = mean|H_LS - H_DFT|^2,
%     sigma_old^2 = mean|H_old - H_LS|^2 recorded below.  The exact
%     book variance definitions and the subscript order remain
%     BLOCKED-SOURCE-REVIEW pending book/17.png.
%   The fixed-rho linear mixing previously used here is NOT (3-92) and
%   has been removed (spec 3.6).
%   A_k uses the exact recovered (3-86)/(3-87) form from book/P67.png:
%   Lambda_k = conj(H_k) Sigma_k / (|H_k|^2 Sigma_k + N sigma_w^2),
%   Gamma = mean(Lambda .* H); implemented in
%   ch3_ibdfe_coefficients.m (no flooring; invalid denominators raise).
%   The previous H*-form A_k with the missing N factor is superseded.
N = cfg.fftSize;
Y = fft(receivedData);
feedbackSpectrum = complex(zeros(1, N));
reliability = 0;
trace.errorCurve = zeros(1, cfg.ibdfeIterations);
trace.reliability = zeros(1, cfg.ibdfeIterations);
trace.feedforward = complex(zeros(cfg.ibdfeIterations, N));
trace.feedback = complex(zeros(cfg.ibdfeIterations, N));
trace.feedbackMeans = complex(zeros(cfg.ibdfeIterations, N));
trace.normalization = complex(zeros(1, cfg.ibdfeIterations));
trace.channelHistory = complex(zeros(cfg.ibdfeIterations, N));
trace.feedbackMode = string(feedbackMode);
trace.updatesChannel = logical(updateChannel);
trace.lambdaHistory = complex(zeros(cfg.ibdfeIterations, N));
trace.gammaHistory = complex(zeros(1, cfg.ibdfeIterations));
trace.sigmaHistory = complex(zeros(cfg.ibdfeIterations, N));
if updateChannel
    trace.iceSigma0Squared = zeros(1, cfg.ibdfeIterations);
    trace.iceSigmaDftSquared = zeros(1, cfg.ibdfeIterations);
end
% (3-92) variance policy resolved up front (see the ICE update block):
% strict-explicit requires source variances, engineering-residual uses
% residual-energy estimates and is recorded as ENGINEERING (never BOOK).
if updateChannel
    trace.iceVarianceMode = "engineering-residual";
    if isfield(cfg, "iceVarianceMode") && ~isempty(cfg.iceVarianceMode)
        trace.iceVarianceMode = lower(string(cfg.iceVarianceMode));
    end
    if trace.iceVarianceMode == "strict-explicit"
        if ~isfield(cfg, "iceSigma0Squared") || ...
                ~isfield(cfg, "iceSigmaDftSquared") || ...
                isempty(cfg.iceSigma0Squared) || ...
                isempty(cfg.iceSigmaDftSquared)
            error("SCFDE:BookParameterUnavailable", ...
                "strict-explicit (3-92) fusion requires cfg.iceSigma0Squared and cfg.iceSigmaDftSquared (the exact variance estimator is not recovered from the source).");
        end
    elseif trace.iceVarianceMode ~= "engineering-residual"
        error("SCFDE:InvalidOption", ...
            "cfg.iceVarianceMode must be engineering-residual or strict-explicit.");
    end
end
% Weakest-link certification (2026-08-17): the plain SD/HD IBDFE chain is
% complete once (3-86)/(3-87) are implemented and oracle-locked
% (book/P67.png) - the ICE chain additionally includes the (3-92)
% variance DEFINITIONS (still BLOCKED-SOURCE-REVIEW, book/P68.png), so
% only the ICE paths stay blocked.
trace.formulaStatus = "BLOCKED-SOURCE-REVIEW";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = struct("iterations", cfg.ibdfeIterations, ...
    "fftSize", N, "channelEstimateLength", cfg.channelEstimateLength, ...
    "noiseVariance", noiseVariance, "feedbackMode", string(feedbackMode), ...
    "updatesChannel", logical(updateChannel));
if updateChannel
    trace.formulaNote = "(3-64)~(3-87) verified incl. (3-86)/(3-87) from book/P67.png; (3-92) fusion OWN-weight ordering from book/P68.png; variance VALUES are a caller policy (engineering-residual = ENGINEERING, strict-explicit = source variances) - the exact estimator is NOT recovered -> ICE weakest-link certification stays BLOCKED-SOURCE-REVIEW";
else
    trace.formulaStatus = "BOOK-EXACT";
    trace.formulaNote = "(3-64)~(3-87) verified: C=Lambda/Gamma, B=CH-1, unit gain, iteration 1 = MMSE-FDE degradation with N*sigma_w^2 per (3-86)/(3-87) (book/P67.png); first-iteration filter oracle-locked in test_ch3_fde_ibdfe_eq_3_39_92";
end
trace.channelUpdateStatus = "ENGINEERING-BLOCKED";
trace.channelUpdateNote = "(3-88)~(3-91) LS + DFT truncation implemented (book/P68.png confirms H_LS = R/X_D^0); (3-92) fusion applied with the recovered OWN-weight ordering (H_old*sigma_old^2 + H_DFT*sigma_DFT^2)/(sigma_old^2+sigma_DFT^2), book/P68.png - the cross-weight ordering is rejected by the oracle; variance VALUES: engineering-residual (residual energies, ENGINEERING) or strict-explicit (cfg.iceSigma0Squared/iceSigmaDftSquared); the exact variance estimator is not recovered from the source";

for iteration = 1:cfg.ibdfeIterations
    symbolVariance = max(1 - reliability, eps);
    % (3-86)/(3-87) exact coefficients (book/P67.png): the N*sigma_w^2
    % term is REQUIRED; invalid denominators raise instead of flooring.
    [feedforward, feedback, lambda, gamma] = ...
        scfde.equalizers.ch3_ibdfe_coefficients( ...
        H, symbolVariance, noiseVariance, N);
    trace.normalization(iteration) = mean(feedforward .* H);
    trace.lambdaHistory(iteration, :) = lambda;
    trace.gammaHistory(iteration) = gamma;
    trace.sigmaHistory(iteration, :) = symbolVariance;
    estimateSpectrum = feedforward .* Y - feedback .* feedbackSpectrum;
    symbols = ifft(estimateSpectrum);

    hardDecision = scfde.equalizers.ch3_qpsk_map(scfde.equalizers.ch3_qpsk_demap(symbols));
    if feedbackMode == "soft"
        feedbackMean = scfde.equalizers.ch3_qpsk_posterior_mean(symbols, noiseVariance);
        reliability = min(0.999, mean(abs( ...
            feedbackMean(1:cfg.dataSymbols)).^2));
    else
        feedbackMean = hardDecision;
        reliability = scfde.equalizers.ch3_symbol_reliability( ...
            symbols(1:cfg.dataSymbols), noiseVariance);
    end
    feedbackMean(cfg.dataSymbols + 1:end) = uw;
    feedbackSpectrum = fft(feedbackMean);

    if updateChannel && iteration > 1
        % (3-88)/(3-89): LS channel from the current soft/hard estimates,
        % H_LS = R ./ X_bar = R .* conj(X_bar) ./ |X_bar|^2 (numerically
        % safe complex division with a floor only on the denominator
        % magnitude - the book form R/X_D^0 confirmed against book/P68.png).
        softSpectrum = fft(feedbackMean);
        hLs = Y .* conj(softSpectrum) ./ max(abs(softSpectrum).^2, eps);
        % (3-90)/(3-91): DFT-domain truncation to channelEstimateLength.
        hEst = ifft(hLs);
        hDft = hEst;
        hDft(cfg.channelEstimateLength + 1:end) = 0;
        hDftSpectrum = fft(hDft);
        % (3-92) fusion with the recovered OWN-weight ordering
        % (book/P68.png): each branch weighted by ITS OWN variance.
        % The variance VALUES follow the resolved policy (see init):
        %   engineering-residual: residual-energy estimates, recorded as
        %     ENGINEERING (never labelled BOOK);
        %   strict-explicit: cfg.iceSigma0Squared / cfg.iceSigmaDftSquared
        %     used verbatim (missing fields raise earlier).
        if trace.iceVarianceMode == "strict-explicit"
            sigma0Sq = cfg.iceSigma0Squared;
            sigmaDftSq = cfg.iceSigmaDftSquared;
        else
            sigmaDftSq = mean(abs(hLs - hDftSpectrum).^2);
            sigma0Sq = mean(abs(H - hLs).^2);
        end
        H = scfde.equalizers.ch3_channel_estimate_fuse( ...
            H, hDftSpectrum, sigma0Sq, sigmaDftSq);
        trace.iceSigma0Squared(iteration) = sigma0Sq;
        trace.iceSigmaDftSquared(iteration) = sigmaDftSq;
    end
    trace.channelHistory(iteration, :) = H;

    hardDecision(cfg.dataSymbols + 1:end) = uw;
    trace.errorCurve(iteration) = mean(abs(symbols - hardDecision).^2);
    trace.reliability(iteration) = reliability;
    trace.feedforward(iteration, :) = feedforward;
    trace.feedback(iteration, :) = feedback;
    trace.feedbackMeans(iteration, :) = feedbackMean;
end
assert(max(abs(trace.normalization - 1)) < 1e-10, ...
    "IBDFE feedforward coefficients violate the unit-gain constraint.");
end
