function [decisions, mse, estimates, trace] = known_dfe_core(received, reference, impulse, cfg)
%KNOWN_DFE_CORE Strict known-channel Wiener DFE (book (2-6)~(2-11)).
%   Phase 1 (training): solve the sample Wiener solution
%       w = R_u^{-1} r_du,   R_u = E[u_k u_k^H],  r_du = E[u_k d_k^*],
%   by least squares over the training segment on the composite vector
%       u_k = [ r(k+D) ... r(k+D-Nf+1); -d(k-1) ... -d(k-Nb) ]^T,
%   which is the empirical estimate of (2-8)~(2-10).  Regularization is
%   applied only when the training matrix is rank-deficient (the `\`
%   minimum-norm solution); no SNR-dependent floors are added.
%   Phase 2 (data): the filter is FIXED - (2-6)~(2-11) define a static
%   Wiener DFE with decision-directed feedback and NO adaptation (the
%   previous data-phase NLMS tracking is removed).
%   Fallback: when the training segment is shorter than Nf+Nb, a
%   regularized MMSE feedforward solve is used (ENGINEERING fallback,
%   recorded in trace.solveMode).
received = received(:).';
reference = reference(:).';
if ~isfield(cfg, "nlmsStep")
    cfg.nlmsStep = 0.35;   % legacy callers only; unused on this path
end
if ~isfield(cfg, "lmsStep")
    cfg.lmsStep = 0.008;   % legacy callers only; unused on this path
end
feedforwardLength = cfg.feedforwardTaps;
feedbackLength = cfg.feedbackTaps;
delay = min(ceil(numel(impulse) / 2), feedforwardLength - 1);
ff = feedforwardLength;
fb = feedbackLength;
trainingIdx = delay + 1:min(cfg.trainingSymbols, numel(reference));
nTr = numel(trainingIdx);
trace = scfde.equalizers.initialize_trace(reference, ff + fb);
if nTr >= ff + fb
    Uff = zeros(nTr, ff);
    Ufb = zeros(nTr, fb);
    for k = 1:nTr
        idx = trainingIdx(k);
        oi = idx + delay;
        winStart = max(1, oi - ff + 1);
        win = received(winStart:oi);
        % Conjugate rows: prediction is X*w = w^H u, matching the
        % inference inner product w'*input (and the book form d_hat = w^H u).
        Uff(k, end - numel(win) + 1:end) = conj(win(end:-1:1));
        for t = 1:min(fb, idx - 1)
            Ufb(k, t) = conj(reference(idx - t));
        end
    end
    w = [Uff, -Ufb] \ conj(reference(trainingIdx)).';
    wff = w(1:ff);
    wfb = w(ff + 1:end);
    solveMode = "training-ls-wiener";
else
    % Engineering fallback: regularized MMSE feedforward solve.
    convolutionLength = numel(impulse) + ff - 1;
    channelMatrix = zeros(convolutionLength, ff);
    for tapIndex = 1:ff
        channelMatrix(tapIndex:tapIndex + numel(impulse) - 1, tapIndex) = impulse(:);
    end
    target = zeros(convolutionLength, 1);
    target(delay + 1) = 1;
    signalPower = mean(abs(received(1:min(numel(received), ...
        max(ff, numel(reference))))).^2);
    noisePower = signalPower * 10^(-cfg.snrDb / 10);
    noiseVariance = noisePower / max(signalPower, eps);
    wff = (channelMatrix' * channelMatrix + ...
        noiseVariance * eye(ff)) \ (channelMatrix' * target);
    wfb = zeros(fb, 1);
    solveMode = "mmse-ff-fallback";
end
% Fixed-filter decision-directed DFE over the whole frame; no weight
% adaptation in the data phase (static Wiener DFE, (2-6)~(2-11)).
decisions = zeros(size(reference));
mse = zeros(size(reference));
estimates = zeros(size(reference));
trace.feedforwardOutput = zeros(size(reference));
trace.feedbackCancellation = zeros(size(reference));
trace.error = zeros(size(reference));
trace.phase = zeros(size(reference));
trace.frequency = zeros(size(reference));
trace.weightNorm = zeros(size(reference));
trace.coefficientHistory = zeros(ff + fb, numel(reference));
weights = [wff(:); wfb(:)];
for symbolIndex = max(delay + 1, ff):numel(reference)
    observationIndex = symbolIndex + delay;
    if observationIndex > numel(received)
        break;
    end
    winStart = max(1, observationIndex - ff + 1);
    win = received(winStart:observationIndex);
    input = [win(end:-1:1).'; ...
        -decisions(symbolIndex - 1:-1:max(1, symbolIndex - fb)).'];
    input = input(1:ff + fb);
    estimate = weights(1:ff)' * input(1:ff) + ...
        weights(ff + 1:end)' * input(ff + 1:end);
    estimates(symbolIndex) = estimate;
    trace.feedforwardOutput(symbolIndex) = weights(1:ff)' * input(1:ff);
    trace.feedbackCancellation(symbolIndex) = ...
        -weights(ff + 1:end)' * input(ff + 1:end);
    if symbolIndex <= cfg.trainingSymbols
        decisions(symbolIndex) = reference(symbolIndex);
    else
        decisions(symbolIndex) = scfde.equalizers.slice_decision(estimate, cfg);
    end
    error = decisions(symbolIndex) - estimate;
    mse(symbolIndex) = abs(reference(symbolIndex) - estimate)^2;
    trace.error(symbolIndex) = reference(symbolIndex) - estimate;
    trace.weightNorm(symbolIndex) = norm(weights);
    trace.coefficientHistory(:, symbolIndex) = weights;
end
trace.solveMode = solveMode;
trace.adaptation = "none";
trace.decisionDelay = delay;
trace.feedforwardTaps = ff;
trace.feedbackTaps = fb;
% Explicit final-weight record: the coefficientHistory tail columns may
% be preallocated zeros (symbols beyond the processed window), so the
% final coefficients are exposed through a dedicated field together
% with the last processed symbol index.
trace.finalCoefficients = weights;
trace.lastProcessedSymbol = find(trace.weightNorm ~= 0, 1, "last");
if isempty(trace.lastProcessedSymbol)
    trace.lastProcessedSymbol = 0;
end
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = struct("feedforwardTaps", ff, ...
    "feedbackTaps", fb, "decisionDelay", delay, ...
    "solveMode", string(solveMode), "trainingSymbols", cfg.trainingSymbols);
trace.formulaNote = "(2-6)~(2-11) static Wiener DFE: w = R_u^{-1} r_du via training LS; fixed filter in the data phase";
end
