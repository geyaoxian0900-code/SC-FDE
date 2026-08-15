function [decisions, mse, estimates, trace] = multibranch_known_dfe_core( ...
        branches, reference, cfg, equivalents)
%MULTIBRANCH_KNOWN_DFE_CORE P-branch known Wiener DFE with a shared
% feedback branch (book (2-49) post-stage):
%       d_hat(n) = sum_p a_p^H y_p(n) - b^H d~(n).
%   Phase 1 (training): least squares over the training segment on the
%   composite vector u = [y_1 windows; ...; y_P windows; -d~], the
%   empirical estimate of the Wiener solution (2-8)~(2-10) generalized
%   to P feedforward branches.
%   Phase 2 (data): the filter is FIXED (decision-directed feedback, no
%   adaptation).
%   Fallback: when the training segment is shorter than P*Nf+Nb, a
%   regularized MMSE feedforward solve per branch (using the equivalent
%   channels EQUIVALENTS{p} = g_p = sum_k h_k*(-n) * h_k) is used
%   (ENGINEERING fallback, recorded in trace.solveMode).
P = size(branches, 1);
reference = reference(:).';
ff = cfg.feedforwardTaps;
fb = cfg.feedbackTaps;
delay = min(ceil(ff / 3), ff - 1);
trainingIdx = delay + 1:min(cfg.trainingSymbols, numel(reference));
nTr = numel(trainingIdx);
trace = scfde.equalizers.initialize_trace(reference, P * ff + fb);
if nTr >= P * ff + fb
    Uff = zeros(nTr, P * ff);
    Ufb = zeros(nTr, fb);
    for k = 1:nTr
        idx = trainingIdx(k);
        oi = idx + delay;
        for p = 1:P
            winStart = max(1, oi - ff + 1);
            win = branches(p, winStart:oi);
            range = (p - 1) * ff + (1:ff);
            Uff(k, range(end - numel(win) + 1:end)) = conj(win(end:-1:1));
        end
        for t = 1:min(fb, idx - 1)
            Ufb(k, t) = conj(reference(idx - t));
        end
    end
    w = [Uff, -Ufb] \ conj(reference(trainingIdx)).';
    solveMode = "training-ls-wiener";
else
    % Engineering fallback: per-branch regularized MMSE feedforward
    % solve on the equivalent channel g_p; common feedback zero.
    wff = complex(zeros(P * ff, 1));
    for p = 1:P
        g = equivalents{p}(:).';
        convolutionLength = numel(g) + ff - 1;
        channelMatrix = zeros(convolutionLength, ff);
        for tapIndex = 1:ff
            channelMatrix(tapIndex:tapIndex + numel(g) - 1, tapIndex) = g(:);
        end
        target = zeros(convolutionLength, 1);
        target(min(delay + 1, convolutionLength)) = 1;
        signalPower = mean(abs(branches(p, 1:min(size(branches, 2), ...
            max(ff, numel(reference))))).^2);
        noisePower = signalPower * 10^(-cfg.snrDb / 10);
        noiseVariance = noisePower / max(signalPower, eps);
        wff((p - 1) * ff + (1:ff)) = (channelMatrix' * channelMatrix + ...
            noiseVariance * eye(ff)) \ (channelMatrix' * target);
    end
    w = [wff; zeros(fb, 1)];
    solveMode = "mmse-ff-fallback";
end
% Fixed filter over the whole frame (decision-directed feedback).
decisions = zeros(size(reference));
mse = zeros(size(reference));
estimates = zeros(size(reference));
trace.feedforwardOutput = zeros(size(reference));
trace.feedbackCancellation = zeros(size(reference));
trace.error = zeros(size(reference));
trace.phase = zeros(size(reference));
trace.frequency = zeros(size(reference));
trace.weightNorm = zeros(size(reference));
trace.coefficientHistory = zeros(P * ff + fb, numel(reference));
for symbolIndex = max(delay + 1, ff):numel(reference)
    observationIndex = symbolIndex + delay;
    if observationIndex > size(branches, 2)
        break;
    end
    input = zeros(P * ff + fb, 1);
    for p = 1:P
        winStart = max(1, observationIndex - ff + 1);
        win = branches(p, winStart:observationIndex);
        range = (p - 1) * ff + (1:ff);
        input(range(end - numel(win) + 1:end)) = win(end:-1:1);
    end
    input(P * ff + 1:end) = ...
        -decisions(symbolIndex - 1:-1:max(1, symbolIndex - fb));
    input = input(1:P * ff + fb);
    estimate = w(1:P * ff)' * input(1:P * ff) + ...
        w(P * ff + 1:end)' * input(P * ff + 1:end);
    estimates(symbolIndex) = estimate;
    trace.feedforwardOutput(symbolIndex) = w(1:P * ff)' * input(1:P * ff);
    trace.feedbackCancellation(symbolIndex) = ...
        -w(P * ff + 1:end)' * input(P * ff + 1:end);
    if symbolIndex <= cfg.trainingSymbols
        decisions(symbolIndex) = reference(symbolIndex);
    else
        decisions(symbolIndex) = scfde.equalizers.slice_decision(estimate, cfg);
    end
    mse(symbolIndex) = abs(reference(symbolIndex) - estimate)^2;
    trace.error(symbolIndex) = reference(symbolIndex) - estimate;
    trace.weightNorm(symbolIndex) = norm(w);
    trace.coefficientHistory(:, symbolIndex) = w;
end
trace.solveMode = solveMode;
trace.adaptation = "none";
trace.decisionDelay = delay;
trace.branchCount = P;
trace.feedforwardTaps = ff;
trace.feedbackTaps = fb;
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = struct("branchCount", P, ...
    "feedforwardTaps", ff, "feedbackTaps", fb, ...
    "decisionDelay", delay, "solveMode", string(solveMode));
trace.formulaNote = "(2-49) P-branch Wiener DFE: sum_p a_p^H y_p - b^H d~; training LS, fixed filter in the data phase";
end
