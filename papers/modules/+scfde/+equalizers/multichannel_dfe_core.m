function [decisions, mse, estimates, trace] = multichannel_dfe_core(branches, reference, cfg, updateRule)
%MULTICHANNEL_DFE_CORE Shared multichannel adaptive DFE for the equalizer package.
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
firstSymbol = max(feedforwardLength, feedbackLength + delay + 1);
lastSymbol = min(numel(reference), size(branches, 2) - delay);
for symbolIndex = firstSymbol:lastSymbol
    input = zeros(branchCount * feedforwardLength + feedbackLength, 1);
    for branchIndex = 1:branchCount
        range = (branchIndex - 1) * feedforwardLength + (1:feedforwardLength);
        input(range) = branches(branchIndex, symbolIndex + delay:-1: ...
            symbolIndex + delay - feedforwardLength + 1).';
    end
    input(branchCount * feedforwardLength + 1:end) = ...
        -decisions(symbolIndex - 1:-1:symbolIndex - feedbackLength).';
    feedforwardEstimate = weights(1:feedforwardWeightCount)' * ...
        input(1:feedforwardWeightCount);
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
    mse(symbolIndex) = abs(reference(symbolIndex) - estimate)^2;
    trace.error(symbolIndex) = reference(symbolIndex) - estimate;
    trace.weightNorm(symbolIndex) = norm(weights);
    trace.coefficientHistory(:, symbolIndex) = weights;
end
end
