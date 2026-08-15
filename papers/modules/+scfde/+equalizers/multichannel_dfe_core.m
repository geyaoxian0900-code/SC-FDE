function [decisions, mse, estimates, trace] = multichannel_dfe_core(branches, reference, cfg, updateRule)
%MULTICHANNEL_DFE_CORE Shared multichannel adaptive DFE for the equalizer package.
%   Book (2-43)~(2-46): P independent elements, per-element phase loops,
%   coherent sum of the feedforward outputs, shared feedback branch:
%       z(k) = sum_p a_p^H(k) r_p(k) e^{-j theta_p,k} - b^H(k) d~(k)
%   Each element keeps its own second-order DPLL (2-35)/(2-36)/(2-37):
%       phi_p = Im{ p_p (d + q)* },   p_p = a_p^H r_p e^{-j theta_p},
%       q = b^H d~  (positive feedback term),   K2 = 0.1 K1.
%   The adaptive update acts on ONE composite vector
%       u = [r_1 e^{-j theta_1}; ...; r_P e^{-j theta_P}; -d~]
%   with the requested rule: LMS (2-14, mu_a = mu_b = lmsStep/2),
%   NLMS (2-16) or RLS (2-23)~(2-25) with P spanning the full
%   P*Nf + Nb dimension.  The update is applied AFTER the phase loops.
reference = reference(:).';
feedforwardLength = cfg.feedforwardTaps;
feedbackLength = cfg.feedbackTaps;
delay = min(ceil(feedforwardLength / 3), feedforwardLength - 1);
branchCount = size(branches, 1);
weights = zeros(branchCount * feedforwardLength + feedbackLength, 1);
for branchIndex = 1:branchCount
    weights((branchIndex - 1) * feedforwardLength + delay + 1) = 1 / branchCount;
end
inverseCorrelation = scfde.equalizers.initial_inverse_correlation(numel(weights), cfg, updateRule);
decisions = zeros(size(reference));
mse = zeros(size(reference));
estimates = zeros(size(reference));
feedforwardWeightCount = branchCount * feedforwardLength;
trace = scfde.equalizers.initialize_trace(reference, numel(weights));
% Per-element DPLL state (independent loops, (2-43)~(2-46)).
K1 = 0.020;
K2 = 0.002;                          % K2 = 0.1 K1 (book (2-37))
if isfield(cfg, "dpllProportionalGain"), K1 = cfg.dpllProportionalGain; end
if isfield(cfg, "dpllIntegralGain"), K2 = cfg.dpllIntegralGain; end
phases = zeros(1, branchCount);
frequencies = zeros(1, branchCount);
trace.phases = zeros(branchCount, numel(reference));
trace.frequencies = zeros(branchCount, numel(reference));
trace.branchFeedforwardOutputs = complex(zeros(branchCount, numel(reference)));
trace.inputHistory = complex(zeros(numel(weights), numel(reference)));
trace.parameters = struct("elementCount", branchCount, ...
    "feedforwardTaps", feedforwardLength, "feedbackTaps", feedbackLength, ...
    "decisionDelay", delay, "updateRule", string(updateRule), ...
    "dpllProportionalGain", K1, "dpllIntegralGain", K2);
firstSymbol = max(feedforwardLength, feedbackLength + delay + 1);
lastSymbol = min(numel(reference), size(branches, 2) - delay);
for symbolIndex = firstSymbol:lastSymbol
    input = zeros(branchCount * feedforwardLength + feedbackLength, 1);
    branchOutputs = zeros(1, branchCount);
    for branchIndex = 1:branchCount
        range = (branchIndex - 1) * feedforwardLength + (1:feedforwardLength);
        input(range) = branches(branchIndex, symbolIndex + delay:-1: ...
            symbolIndex + delay - feedforwardLength + 1).' .* ...
            exp(-1j * phases(branchIndex));
        branchOutputs(branchIndex) = weights(range)' * input(range);
    end
    input(branchCount * feedforwardLength + 1:end) = ...
        -decisions(symbolIndex - 1:-1:symbolIndex - feedbackLength).';
    feedforwardEstimate = sum(branchOutputs);
    feedbackTerm = weights(feedforwardWeightCount + 1:end)' * ...
        input(feedforwardWeightCount + 1:end);
    estimate = feedforwardEstimate + feedbackTerm;
    estimates(symbolIndex) = estimate;
    trace.feedforwardOutput(symbolIndex) = feedforwardEstimate;
    trace.feedbackCancellation(symbolIndex) = -feedbackTerm;
    if symbolIndex <= cfg.trainingSymbols
        decisions(symbolIndex) = reference(symbolIndex);
    else
        decisions(symbolIndex) = scfde.equalizers.slice_decision(estimate, cfg);
    end
    error = decisions(symbolIndex) - estimate;
    [weights, inverseCorrelation] = scfde.equalizers.adaptive_update(weights, inverseCorrelation, ...
        input, error, cfg, updateRule);
    % Per-element phase detector (2-36): phi_p = Im{ p_p (d + q)* } with
    % q = b^H d~ positive; feedbackTerm stores -q, so
    % Im{p_p conj(q)} = -Im{p_p conj(feedbackTerm)}.
    for branchIndex = 1:branchCount
        phaseError = imag(branchOutputs(branchIndex) * ...
            conj(decisions(symbolIndex))) - ...
            imag(branchOutputs(branchIndex) * conj(feedbackTerm));
        frequencies(branchIndex) = frequencies(branchIndex) + K2 * phaseError;
        phases(branchIndex) = phases(branchIndex) + ...
            frequencies(branchIndex) + K1 * phaseError;
    end
    trace.phases(:, symbolIndex) = phases;
    trace.frequencies(:, symbolIndex) = frequencies;
    trace.branchFeedforwardOutputs(:, symbolIndex) = branchOutputs;
    trace.inputHistory(:, symbolIndex) = input;
    mse(symbolIndex) = abs(reference(symbolIndex) - estimate)^2;
    trace.error(symbolIndex) = reference(symbolIndex) - estimate;
    trace.weightNorm(symbolIndex) = norm(weights);
    trace.coefficientHistory(:, symbolIndex) = weights;
end
end
