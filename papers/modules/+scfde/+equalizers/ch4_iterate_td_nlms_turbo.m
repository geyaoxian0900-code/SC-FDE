function [bits, curve, trace] = ch4_iterate_td_nlms_turbo(received, Y, ...
        Hinitial, Hreference, noiseVariance, frame, cfg) %#ok<INUSD>
%CH4_ITERATE_TD_NLMS_TURBO Time-domain direct-adaptive turbo equalization
% (spec 4.8, boxed LMS form - project combination, at most ALG-EQUIV):
%     z(n)     = w_f^H(n) r_n - w_b^H(n) x_bar_{n-1}
%     e(n)     = d_a(n) - z(n),   d_a = d (training) / E[x|L_D^e] (data)
%     w_f(n+1) = w_f(n) + mu_f r_n e*(n)
%     w_b(n+1) = w_b(n) - mu_b x_bar_{n-1} e*(n)
%   Initial weights are ZERO (spec 4.8: no true-channel initial
%   weights).  The update is the boxed UNNORMALIZED LMS (the previous
%   NLMS normalization is removed).
%
%   Boundary rules (frame-start conventions, recorded in the trace):
%     * r_n = [r(n); r(n-1); ...; r(n-Nf+1)] is a CAUSAL window with
%       ZERO padding before the frame head (no circular wrap: the
%       frame-tail coded data must never leak into the frame-head
%       training regressors).
%     * x_bar_{n-1} is zero-padded before the frame head (no prior).
%     * First round has NO data prior (spec 4.8 gives no
%       channel-assisted MMSE initialization): the data soft symbols
%       start at zero, so the data segment has no target d_a yet and
%       iteration 1 adapts on the TRAINING segment only; the data
%       segment is only equalized.  Iterations >= 2 use the decoder
%       extrinsic mean E[x|L_D^e] on the data segment and adapt there.
%   Y/Hinitial are accepted for interface compatibility but UNUSED: no
%   true-channel quantity may seed the first-round soft feedback.
%   Hreference (optional, pass [] to skip) is used ONLY for the
%   trace-only channel NMSE metric, never inside the adaptation.
%   BCJR sees only the coded-data LLRs and returns exactly 512
%   information bits; the BOOK path is undamped.
%
%   Mean-convergence bound (theoretical diagnostic ONLY, recorded per
%   round): the joint-regressor quantity
%     2/lambda_max(R_hat),  u_n = [r_n; -x_bar_{n-1}],  R_hat = mean_n
%     u_n u_n^H, is an independence-based MEAN-convergence reference,
%     NOT a stability guarantee for the decision-feedback
%     non-stationary trajectory (mu below it can still diverge, as
%     observed).  It is re-measured EVERY round with that round's soft
%     symbols (round 1: no-prior; rounds >= 2: decoder extrinsic means
%     - the feedback regressor changes, so a round-1-only value cannot
%     cover later rounds).  trace.meanConvergenceBound /
%     trace.withinMeanConvergenceBound are per-round arrays; the
%     overall diagnostic uses the MINIMUM across rounds
%     (trace.minimumMeanConvergenceBound,
%     trace.meanBoundSatisfiedAllIterations).  Actual divergence is
%     judged from the error/weight trajectories (trace.errorPower /
%     trace.trainingErrorPower / trace.finalChannel), never from this
%     diagnostic alone.
N = frame.frameLength;
feedforwardTaps = min(cfg.tdAdaptiveTaps, N);
feedbackTaps = min(cfg.feedbackTaps, N - 1);
% Boxed UNNORMALIZED LMS step.  cfg.tdNlmsStep (default 0.35) is an
% NLMS-era value: for the boxed LMS it EXCEEDS the joint-regressor
% mean-convergence reference 2/lambda_max(R) and diverges (observed
% BER ~0.51).  cfg.tddaMu is the conservative default (measured to be
% about half of that reference on the unit-energy 16-tap turbo input
% at 18 dB), recorded in the trace.
if isfield(cfg, "tddaMu") && ~isempty(cfg.tddaMu)
    muF = cfg.tddaMu;
else
    muF = cfg.tdNlmsStep;
end
muB = muF;                          % boxed mu_b (recorded)
weightsF = complex(zeros(feedforwardTaps, 1));   % zero init (spec 4.8)
weightsB = complex(zeros(feedbackTaps, 1));
% First-round no-prior soft symbols: training locked to d, data = 0
% (NO channel-assisted MMSE initialization).
softSymbols = zeros(1, N);
softSymbols(frame.trainingIndices) = frame.trainingSymbols;
trainMask = false(1, N);
trainMask(frame.trainingIndices) = true;
inputEnergy = mean(abs(received).^2);
feedforwardOnlyMeanBound = 2 / max(feedforwardTaps * inputEnergy, eps);
curve = zeros(1, cfg.iterations);
trace = scfde.equalizers.ch4_initialize_trace(cfg.iterations, N, []);
trace.trainingErrorPower = zeros(1, cfg.iterations);
trace.dataErrorPower = zeros(1, cfg.iterations);
trace.meanConvergenceBound = zeros(1, cfg.iterations);
trace.withinMeanConvergenceBound = false(1, cfg.iterations);
for iteration = 1:cfg.iterations
    % Per-round joint-regressor mean-convergence reference with the
    % CURRENT soft symbols (see header: the feedback regressor changes
    % per round; theoretical diagnostic only, NOT a stability
    % guarantee).
    trace.meanConvergenceBound(iteration) = tdda_joint_mean_bound( ...
        received, softSymbols, feedforwardTaps, feedbackTaps);
    trace.withinMeanConvergenceBound(iteration) = ...
        muF < trace.meanConvergenceBound(iteration);
    residual = zeros(1, N);
    for sampleIndex = 1:N
        inputVector = tdda_causal_window(received, sampleIndex, feedforwardTaps);
        feedbackVector = tdda_feedback_window(softSymbols, sampleIndex, feedbackTaps);
        adaptiveOutput = weightsF' * inputVector - ...
            weightsB' * feedbackVector;
        residual(sampleIndex) = softSymbols(sampleIndex) - adaptiveOutput;
        % Iteration 1: no data prior -> no data target d_a -> adapt on
        % the training segment only.  Iterations >= 2: d_a = E[x|L_D^e]
        % is defined on the data segment, adapt everywhere.
        if iteration > 1 || trainMask(sampleIndex)
            weightsF = weightsF + muF * inputVector * conj(residual(sampleIndex));
            weightsB = weightsB - muB * feedbackVector * conj(residual(sampleIndex));
        end
    end
    estimate = zeros(1, N);
    for sampleIndex = 1:N
        inputVector = tdda_causal_window(received, sampleIndex, feedforwardTaps);
        feedbackVector = tdda_feedback_window(softSymbols, sampleIndex, feedbackTaps);
        estimate(sampleIndex) = weightsF' * inputVector - ...
            weightsB' * feedbackVector;
    end
    equalizerLlr = 2 * real(estimate) / noiseVariance;
    [bits, decoderLlr, softSymbols] = ...
        scfde.equalizers.ch4_decoder_feedback_frame( ...
            equalizerLlr, frame, softSymbols, 1, "Log-MAP");
    weightSpectrum = fft([weightsF.', zeros(1, N - feedforwardTaps)]);
    curve(iteration) = mean(bits ~= frame.informationBits);
    trace = scfde.equalizers.ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, []);
    trace.softEstimates(iteration, :) = estimate;
    trace.frequencyWeights(iteration, :) = weightSpectrum;
    if ~isempty(Hreference)
        trace.weightNmse(iteration) = scfde.equalizers.ch4_channel_nmse( ...
            weightSpectrum, ...
            scfde.equalizers.ch4_normalized_mmse(Hreference, noiseVariance));
    else
        trace.weightNmse(iteration) = NaN;   % no true-channel reference
    end
    trace.errorPower(iteration) = mean(abs(residual).^2);
    trace.trainingErrorPower(iteration) = ...
        mean(abs(residual(frame.trainingIndices)).^2);
    trace.dataErrorPower(iteration) = ...
        mean(abs(residual(frame.dataIndices)).^2);
end
trace.minimumMeanConvergenceBound = min(trace.meanConvergenceBound);
trace.meanBoundSatisfiedAllIterations = ...
    muF < trace.minimumMeanConvergenceBound;
trace.finalChannel = fft([weightsF.', zeros(1, N - feedforwardTaps)]);
trace.formulaStatus = "ALG-EQUIV";
trace.formulaMode = "project-combination";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = struct("muF", muF, "muB", muB, ...
    "feedforwardTaps", feedforwardTaps, "feedbackTaps", feedbackTaps, ...
    "iterations", cfg.iterations, "frameLength", N, ...
    "inputEnergy", inputEnergy);
trace.feedforwardOnlyMeanBound = feedforwardOnlyMeanBound;
trace.formulaNote = "spec 4.8 boxed TD direct-adaptive DFE: unnormalized LMS updates with mu_f/mu_b, d_a = d (training) / E[x|L_D^e] (data), ZERO initial weights; iteration 1 has NO data prior (no true-channel MMSE init, adapts on the training segment only), iterations >= 2 adapt everywhere; causal r_n window zero-padded at the frame head (no circular wrap, frame-tail data cannot leak into frame-head training); the joint-regressor quantity 2/lambda_max(R_hat), u_n = [r_n; -x_bar_{n-1}], is re-measured per round and recorded as meanConvergenceBound - an independence-based MEAN-convergence reference, a theoretical diagnostic that is NOT a stability guarantee for the decision-feedback trajectory (mu below it can still diverge); actual divergence is judged from errorPower/trainingErrorPower/finalChannel";
trace.stepParameters = struct("muF", muF, "muB", muB, ...
    "feedforwardTaps", feedforwardTaps, "feedbackTaps", feedbackTaps);
end

function window = tdda_causal_window(received, sampleIndex, taps)
% Causal window r_n = [r(n); r(n-1); ...; r(n-taps+1)] with ZERO padding
% before the frame head (no circular wrap).
if sampleIndex >= taps
    window = received(sampleIndex:-1:sampleIndex - taps + 1).';
else
    window = [received(sampleIndex:-1:1).'; ...
        complex(zeros(taps - sampleIndex, 1))];
end
end

function feedback = tdda_feedback_window(softSymbols, sampleIndex, taps)
% x_bar_{n-1} = [x_bar(n-1); ...; x_bar(n-taps)] with zero padding at the
% frame head (no prior before the frame).
feedback = complex(zeros(taps, 1));
if sampleIndex > 1
    count = min(taps, sampleIndex - 1);
    feedback(1:count) = softSymbols(sampleIndex - 1:-1:sampleIndex - count).';
end
end

function meanBound = tdda_joint_mean_bound(received, softSymbols, ...
    feedforwardTaps, feedbackTaps)
% Joint-regressor MEAN-convergence reference for the boxed unnormalized
% LMS (theoretical diagnostic only):
%     u_n = [r_n; -x_bar_{n-1}],  R_hat = mean_n u_n u_n^H,
%     reference = 2 / lambda_max(R_hat).
% This is the standard unnormalized-LMS step condition expressed through
% the joint regressor covariance, but it is an independence-based
% MEAN-convergence approximation and is NOT a stability guarantee for
% the decision-feedback non-stationary trajectory (mu below it can still
% diverge; observed).  Measured with the soft symbols CURRENT for the
% round being started (round 1: no-prior; rounds >= 2: decoder extrinsic
% means).
N = numel(received);
accumulator = complex(zeros(feedforwardTaps + feedbackTaps));
for sampleIndex = 1:N
    regressor = [tdda_causal_window(received, sampleIndex, feedforwardTaps); ...
        -tdda_feedback_window(softSymbols, sampleIndex, feedbackTaps)];
    accumulator = accumulator + regressor * regressor';
end
covariance = (accumulator + accumulator') / 2 / N;  % Hermitian cleanup
lambdaMax = max(real(eig(covariance)));
meanBound = 2 / max(lambdaMax, eps);
end
