function [decisions, mse, estimates, trace] = known_dfe_core(received, reference, impulse, cfg)
%KNOWN_DFE_CORE Shared known-channel DFE implementation for the equalizer package.
%   Joint feedforward + feedback weights solved from the training segment
%   (least squares on known symbols; the LMS adaptive DFE converges in
%   the same solution space).  This replaces the pure-feedforward MMSE
%   solve, which focused too weakly on channels whose matched-filter
%   spectrum |H|^2 has deep nulls (passive time reversal front ends),
%   leaving BER at ~0.5.  Fallback to the MMSE feedforward solve when the
%   training segment is shorter than the filter span.
received = received(:).';
reference = reference(:).';
if ~isfield(cfg, "nlmsStep")
    cfg.nlmsStep = 0.35;
end
if ~isfield(cfg, "lmsStep")
    cfg.lmsStep = 0.008;
end
feedforwardLength = cfg.feedforwardTaps;
feedbackLength = cfg.feedbackTaps;
delay = min(ceil(numel(impulse) / 2), feedforwardLength - 1);
ff = feedforwardLength;
fb = feedbackLength;
trainingIdx = delay + 1:min(cfg.trainingSymbols, numel(reference));
nTr = numel(trainingIdx);
if nTr >= ff + fb
    Xff = zeros(nTr, ff);
    Xfb = zeros(nTr, fb);
    for k = 1:nTr
        idx = trainingIdx(k);
        oi = idx + delay;
        winStart = max(1, oi - ff + 1);
        win = received(winStart:oi);
        % Conjugate rows: prediction is X*w = w^H x, matching the
        % inference inner product weights'*input (and the LMS rule).
        Xff(k, end - numel(win) + 1:end) = conj(win(end:-1:1));
        for t = 1:min(fb, idx - 1)
            Xfb(k, t) = conj(reference(idx - t));
        end
    end
    w = [Xff, -Xfb] \ conj(reference(trainingIdx)).';
    wff = w(1:ff);
    wfb = w(ff + 1:end);
else
    % Fallback: MMSE feedforward solve (see original derivation).
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
end
effectiveChannel = conv(wff, impulse(:));
equalized = filter(wff, 1, received);
decisions = zeros(size(reference));
mse = zeros(size(reference));
estimates = zeros(size(reference));
trace.feedforwardOutput = zeros(size(reference));
trace.feedbackCancellation = zeros(size(reference));
trace.error = zeros(size(reference));
trace.weightNorm = norm([wff; wfb]) * ones(size(reference));
trace.coefficientHistory = zeros(numel(wff) + fb, 0);
trace.phase = zeros(size(reference));
trace.frequency = zeros(size(reference));
weights = [wff(:); wfb(:)];
invCorr = scfde.equalizers.initial_inverse_correlation(numel(weights), cfg, "nlms");
for symbolIndex = max(delay + 1, ff):numel(reference)
    observationIndex = symbolIndex + delay;
    if observationIndex > numel(equalized)
        break;
    end
    winStart = max(1, observationIndex - ff + 1);
    win = received(winStart:observationIndex);
    input = [win(end:-1:1).'; -decisions(symbolIndex - 1:-1:max(1, symbolIndex - fb)).'];
    input = input(1:ff + fb);
    estimate = weights(1:ff)' * input(1:ff) + ...
        weights(ff + 1:end)' * input(ff + 1:end);
    estimates(symbolIndex) = estimate;
    trace.feedforwardOutput(symbolIndex) = equalized(observationIndex);
    trace.feedbackCancellation(symbolIndex) = ...
        -weights(ff + 1:end)' * input(ff + 1:end);
    if symbolIndex <= cfg.trainingSymbols
        decisions(symbolIndex) = reference(symbolIndex);
    else
        decisions(symbolIndex) = scfde.equalizers.slice_decision(estimate, cfg);
    end
    error = decisions(symbolIndex) - estimate;
    [weights, invCorr] = scfde.equalizers.adaptive_update(weights, invCorr, ...
        input, error, cfg, "nlms");
    wff = weights(1:ff);
    wfb = weights(ff + 1:end);
    mse(symbolIndex) = abs(estimate - reference(symbolIndex))^2;
    trace.error(symbolIndex) = reference(symbolIndex) - estimate;
    trace.weightNorm(symbolIndex) = norm(weights);
    trace.coefficientHistory(:, symbolIndex) = weights;
end
end
