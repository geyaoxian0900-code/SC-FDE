function [decisions, mse, estimates, trace] = multichannel_dpll_dfe_core( ...
        subarrayOutputs, reference, cfg)
%MULTICHANNEL_DPLL_DFE_CORE  Multichannel time-domain DFE with one
% second-order DPLL per sub-array (book (2-26)~(2-43), (2-43)~(2-46)):
% the HTF-DFE backend that runs on the (3-61)/(3-62) sub-array outputs.
%
%   p_m(n) = a_m^H x_m(n) e^{-j theta_m(n)}
%   p(n)   = sum_{m=1..P} p_m(n);   q(n) = b^H d~(n);   z(n) = p(n) - q(n)
%   e(n)   = d(n) - z(n)
%   phi_m(n) = Im{ p_m(n) (d(n) + q(n))* }                  (2-36)
%   theta_m(n+1) = theta_m(n) + K1 phi_m(n)
%                  + K2 sum_{tau=1..n} phi_m(tau),  K2 = 0.1 K1
%                                                            (2-35)/(2-37)
%   a_m <- a_m + muA e*(n) [x_m(n) e^{-j theta_m(n)}]        (2-43)~(2-46)
%   b   <- b   - muB e*(n) d~(n)         (minus sign: z = p - q)
%
%   Each sub-array keeps its own theta/integral DPLL state; the feedback
%   branch is shared.  The phase detector uses the book phase error
%   Im{p_m (d + q)*}, never the equalization error imag(e).  The training
%   region uses the known reference symbols, the data region uses sliced
%   decisions, and the current decision never enters the current symbol's
%   feedback (d~ holds past decisions only).  This module never touches
%   the global RNG.
%
%   INPUTS
%     subarrayOutputs P x N complex matrix (rows = x_m from (3-62))
%     reference       1 x N complex reference/training signal
%     cfg             .feedforwardTaps (Nf), .feedbackTaps (Nb),
%                     .trainingSymbols, .modulation,
%                     .dpllProportionalGain (K1), .dpllIntegralGain (K2),
%                     optional .htfdeMuA/.htfdeMuB (default: lmsStep)
%   OUTPUTS
%     decisions/estimates/mse  1 x N rows over the processed window
%     trace                    phase/phaseError/frequency per sub-array
%                              (P x N) plus the shared DFE diagnostics
P = size(subarrayOutputs, 1);
N = size(subarrayOutputs, 2);
reference = reference(:).';
Nf = cfg.feedforwardTaps;
Nb = cfg.feedbackTaps;
delay = min(ceil(Nf / 3), Nf - 1);
delay = max(1, delay);
if isfield(cfg, "dpllProportionalGain")
    K1 = cfg.dpllProportionalGain;
else
    K1 = 0.020;                          % implementation default, recorded
end
if isfield(cfg, "dpllIntegralGain")
    K2 = cfg.dpllIntegralGain;
else
    K2 = 0.002;                          % K2 = 0.1 K1 (book (2-37))
end
if isfield(cfg, "htfdeMuA")
    muA = cfg.htfdeMuA;
elseif isfield(cfg, "lmsStep")
    muA = cfg.lmsStep;
else
    muA = 0.008;
end
if isfield(cfg, "htfdeMuB")
    muB = cfg.htfdeMuB;
elseif isfield(cfg, "lmsStep")
    muB = cfg.lmsStep;
else
    muB = 0.008;
end

feedforwardWeights = zeros(Nf, P);       % columns = per-subarray a_m
for subarrayIndex = 1:P
    % Implementation initialization (recorded, not a book value):
    % unit combined gain split evenly over the P sub-arrays at the delay tap.
    feedforwardWeights(delay + 1, subarrayIndex) = 1 / P;
end
feedbackWeights = zeros(Nb, 1);
theta = zeros(1, P);
integral = zeros(1, P);
decisions = zeros(size(reference));
mse = zeros(size(reference));
estimates = zeros(size(reference));
weightCount = P * Nf + Nb;
trace.feedforwardOutput = zeros(1, N);
trace.feedbackCancellation = zeros(1, N);
trace.error = zeros(1, N);
trace.weightNorm = zeros(1, N);
trace.coefficientHistory = zeros(weightCount, N);
trace.phase = zeros(P, N);
trace.phaseError = zeros(P, N);
trace.frequency = zeros(P, N);
% Record the effective parameters so downstream metadata can distinguish
% formula-structure verification from book-experiment reproduction (the
% book's own experiment values are PARAM-UNRECOVERABLE).
trace.parameters = struct("subarrayCount", P, ...
    "feedforwardTaps", Nf, "feedbackTaps", Nb, "decisionDelay", delay, ...
    "dpllProportionalGain", K1, "dpllIntegralGain", K2, ...
    "muA", muA, "muB", muB);
dtilde = zeros(Nb, 1);
firstSymbol = max(Nf, Nb + delay + 1);
lastSymbol = min(numel(reference), N - delay);
for n = firstSymbol:lastSymbol
    p = 0;
    pPerSubarray = zeros(1, P);
    rotatedWindow = zeros(Nf, P);
    for subarrayIndex = 1:P
        xm = subarrayOutputs(subarrayIndex, ...
            n + delay:-1:n + delay - Nf + 1).';
        xmRotated = xm * exp(-1j * theta(subarrayIndex));
        pPerSubarray(subarrayIndex) = ...
            feedforwardWeights(:, subarrayIndex)' * xmRotated;
        p = p + pPerSubarray(subarrayIndex);
        rotatedWindow(:, subarrayIndex) = xmRotated;
    end
    q = feedbackWeights' * dtilde;
    z = p - q;
    estimates(n) = z;
    if n <= cfg.trainingSymbols
        d = reference(n);                % training: known symbol
    else
        d = scfde.equalizers.slice_decision(z, cfg);
    end
    decisions(n) = d;
    e = d - z;
    for subarrayIndex = 1:P
        % (2-43)~(2-46) feedforward update with per-subarray rotation.
        feedforwardWeights(:, subarrayIndex) = ...
            feedforwardWeights(:, subarrayIndex) + ...
            muA * conj(e) * rotatedWindow(:, subarrayIndex);
    end
    % Feedback update carries the minus sign of z = p - q.
    feedbackWeights = feedbackWeights - muB * conj(e) * dtilde;
    for subarrayIndex = 1:P
        % Book phase detector (2-36): phi_m = Im{ p_m (d + q)* }.
        phi = imag(pPerSubarray(subarrayIndex) * conj(d + q));
        integral(subarrayIndex) = integral(subarrayIndex) + phi;
        theta(subarrayIndex) = theta(subarrayIndex) + ...
            K1 * phi + K2 * integral(subarrayIndex);
        trace.phaseError(subarrayIndex, n) = phi;
        trace.frequency(subarrayIndex, n) = integral(subarrayIndex);
        trace.phase(subarrayIndex, n) = theta(subarrayIndex);
    end
    dtilde = [d; dtilde(1:end - 1)];
    mse(n) = abs(reference(n) - z)^2;
    trace.feedforwardOutput(n) = p;
    trace.feedbackCancellation(n) = -q;
    trace.error(n) = reference(n) - z;
    trace.weightNorm(n) = norm([feedforwardWeights(:); feedbackWeights]);
    trace.coefficientHistory(:, n) = [feedforwardWeights(:); feedbackWeights];
end
end
