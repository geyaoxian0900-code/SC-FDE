function [decisions, mse, estimates, trace] = adaptive_dfe_core(received, reference, cfg, updateRule, useDpll)
%ADAPTIVE_DFE_CORE Shared adaptive DFE implementation for the equalizer package.
received = received(:).';
reference = reference(:).';
feedforwardLength = cfg.feedforwardTaps;
feedbackLength = cfg.feedbackTaps;
delay = min(ceil(feedforwardLength / 3), feedforwardLength - 1);
weights = zeros(feedforwardLength + feedbackLength, 1);
inverseCorrelation = scfde.equalizers.initial_inverse_correlation(numel(weights), cfg, updateRule);
decisions = zeros(size(reference));
mse = zeros(size(reference));
estimates = zeros(size(reference));
trace = scfde.equalizers.initialize_trace(reference, numel(weights));
phase = 0;
frequency = 0;
firstSymbol = max(feedforwardLength, feedbackLength + delay + 1);
lastSymbol = min(numel(reference), numel(received) - delay);
for symbolIndex = firstSymbol:lastSymbol
    input = [received(symbolIndex + delay:-1: ...
        symbolIndex + delay - feedforwardLength + 1).'; ...
        -decisions(symbolIndex - 1:-1:symbolIndex - feedbackLength).'];
    if useDpll
        input(1:feedforwardLength) = input(1:feedforwardLength) * exp(-1j * phase);
    end
    feedforwardEstimate = weights(1:feedforwardLength)' * input(1:feedforwardLength);
    feedbackTerm = weights(feedforwardLength + 1:end)' * ...
        input(feedforwardLength + 1:end);
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
    if useDpll
        % Book phase detector: phi = Im{ p (shat + q)* } with p the
        % feedforward output and q the feedback term:
        %   Im{p conj(shat)} + Im{p conj(q)}.
        % The previous code computed Im{p (conj(shat) - q)} (missing
        % the conjugate on q and using the wrong sign).
        phaseError = imag(feedforwardEstimate * ...
            conj(decisions(symbolIndex))) + ...
            imag(feedforwardEstimate * conj(feedbackTerm));
        frequency = frequency + cfg.dpllIntegralGain * phaseError;
        phase = phase + frequency + cfg.dpllProportionalGain * phaseError;
    end
    mse(symbolIndex) = abs(reference(symbolIndex) - estimate)^2;
    trace.error(symbolIndex) = reference(symbolIndex) - estimate;
    trace.weightNorm(symbolIndex) = norm(weights);
    trace.coefficientHistory(:, symbolIndex) = weights;
    trace.phase(symbolIndex) = phase;
    trace.frequency(symbolIndex) = frequency;
end
end
