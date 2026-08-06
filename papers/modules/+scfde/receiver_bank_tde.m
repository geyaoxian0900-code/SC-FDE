function receiver = receiver_bank_tde(channel, source, cfg)
%RECEIVER_BANK_TDE Run selectable time-domain equalizers for Chapter 2.

[outputs{1}, curves{1}, estimates{1}, traces{1}] = known_dfe(channel.received, source.tx, ...
    channel.impulse, cfg);
[outputs{2}, curves{2}, estimates{2}, traces{2}] = adaptive_dfe( ...
    channel.received, source.tx, cfg, "lms", false);
[outputs{3}, curves{3}, estimates{3}, traces{3}] = adaptive_dfe( ...
    channel.received, source.tx, cfg, "nlms", false);
[outputs{4}, curves{4}, estimates{4}, traces{4}] = adaptive_dfe( ...
    channel.received, source.tx, cfg, "rls", false);
[outputs{5}, curves{5}, estimates{5}, traces{5}] = adaptive_dfe( ...
    channel.received, source.tx, cfg, "nlms", true);
[outputs{6}, curves{6}, estimates{6}, traces{6}] = multichannel_adaptive_dfe( ...
    channel.branches, source.tx, cfg, "lms");
[outputs{7}, curves{7}, estimates{7}, traces{7}] = multichannel_adaptive_dfe( ...
    channel.branches, source.tx, cfg, "nlms");
[outputs{8}, curves{8}, estimates{8}, traces{8}] = multichannel_adaptive_dfe( ...
    channel.branches, source.tx, cfg, "rls");

timeReversal = conj(fliplr(channel.impulse));
[outputs{9}, curves{9}, estimates{9}, traces{9}] = known_dfe(filter(timeReversal, 1, ...
    channel.received), source.tx, conv(timeReversal, channel.impulse), cfg);
subband = subband_ptr(channel.received, channel.impulse, ...
    cfg.numSubbands, cfg.ptrRegularization, channel.branches, ...
    channel.branchImpulses);
equivalent = scfde.equalizers.subband_equivalent_channel( ...
    channel.impulse, channel.branchImpulses);
[outputs{10}, curves{10}, estimates{10}, traces{10}] = known_dfe(subband, source.tx, ...
    equivalent, cfg);

receiver.names = ["Conventional DFE", "LMS adaptive DFE", ...
    "NLMS adaptive DFE", "RLS adaptive DFE", "DPLL-DFE", ...
    "Multichannel LMS DFE", "Multichannel NLMS DFE", ...
    "Multichannel RLS DFE", "Passive TR-DFE", ...
    "Subband passive TR-DFE"];
receiver.ids = ["dfe", "lms-dfe", "nlms-dfe", "rls-dfe", ...
    "dpll-dfe", "mc-lms-dfe", "mc-nlms-dfe", "mc-rls-dfe", ...
    "ptr-dfe", "subband-ptr-dfe"];
receiver.outputs = outputs;
receiver.learningMse = curves;
receiver.estimates = estimates;
receiver.traces = traces;
[selected, requested] = select_methods(receiver.ids, receiver.names, cfg.methods);
receiver.ids = receiver.ids(selected);
receiver.names = receiver.names(selected);
receiver.outputs = receiver.outputs(selected);
receiver.learningMse = receiver.learningMse(selected);
receiver.estimates = receiver.estimates(selected);
receiver.traces = receiver.traces(selected);
receiver.requestedMethods = requested;
end

function [selected, requested] = select_methods(ids, names, requested)
requested = string(requested);
if isscalar(requested) && strcmpi(requested, "all")
    selected = 1:numel(ids);
    requested = ids;
    return;
end
selected = zeros(1, numel(requested));
for index = 1:numel(requested)
    canonical = canonical_method_id(requested(index));
    match = find(strcmpi(canonical, ids) | ...
        strcmpi(requested(index), names), 1);
    assert(~isempty(match), "SCFDE:UnknownMethod", ...
        "Unknown Chapter 2 method: %s. Available IDs: %s", ...
        requested(index), strjoin(ids, ", "));
    selected(index) = match;
end
assert(numel(unique(selected)) == numel(selected), ...
    "SCFDE:DuplicateMethod", "A Chapter 2 method was selected twice.");
end

function id = canonical_method_id(id)
id = string(id);
if strcmpi(id, "pll-dfe")
    id = "dpll-dfe";
elseif strcmpi(id, "mcdfe")
    id = "mc-nlms-dfe";
end
end

function [decisions, mse, estimates, trace] = known_dfe(received, reference, impulse, cfg)
feedforwardLength = cfg.feedforwardTaps;
feedbackLength = cfg.feedbackTaps;
delay = min(ceil(numel(impulse) / 2), feedforwardLength - 1);
convolutionLength = numel(impulse) + feedforwardLength - 1;
channelMatrix = zeros(convolutionLength, feedforwardLength);
for tapIndex = 1:feedforwardLength
    channelMatrix(tapIndex:tapIndex + numel(impulse) - 1, tapIndex) = impulse(:);
end
target = zeros(convolutionLength, 1);
target(delay + 1) = 1;
weights = (channelMatrix' * channelMatrix + ...
    10^(-cfg.snrDb / 10) * 0.03 * eye(feedforwardLength)) \ ...
    (channelMatrix' * target);
effectiveChannel = conv(weights, impulse(:));
equalized = filter(weights, 1, received);
decisions = zeros(size(reference));
mse = zeros(size(reference));
estimates = zeros(size(reference));
trace.feedforwardOutput = zeros(size(reference));
trace.feedbackCancellation = zeros(size(reference));
trace.error = zeros(size(reference));
trace.weightNorm = norm(weights) * ones(size(reference));
trace.coefficientHistory = zeros(numel(weights), 0);
trace.phase = zeros(size(reference));
trace.frequency = zeros(size(reference));
for symbolIndex = delay + 1:numel(reference)
    observationIndex = symbolIndex + delay;
    if observationIndex > numel(equalized)
        break;
    end
    feedback = 0;
    for tapIndex = 1:min(feedbackLength, symbolIndex - 1)
        channelIndex = delay + tapIndex + 1;
        if channelIndex <= numel(effectiveChannel)
            feedback = feedback + effectiveChannel(channelIndex) * ...
                decisions(symbolIndex - tapIndex);
        end
    end
    estimate = equalized(observationIndex) - feedback;
    estimates(symbolIndex) = estimate;
    trace.feedforwardOutput(symbolIndex) = equalized(observationIndex);
    trace.feedbackCancellation(symbolIndex) = feedback;
    if symbolIndex <= cfg.trainingSymbols
        decisions(symbolIndex) = reference(symbolIndex);
    else
        decisions(symbolIndex) = sign(real(estimate));
    end
    if decisions(symbolIndex) == 0
        decisions(symbolIndex) = 1;
    end
    mse(symbolIndex) = abs(estimate - reference(symbolIndex))^2;
    trace.error(symbolIndex) = reference(symbolIndex) - estimate;
end
end

function [decisions, mse, estimates, trace] = adaptive_dfe(received, reference, cfg, updateRule, useDpll)
received = received(:).';
reference = reference(:).';
feedforwardLength = cfg.feedforwardTaps;
feedbackLength = cfg.feedbackTaps;
delay = min(ceil(feedforwardLength / 3), feedforwardLength - 1);
weights = zeros(feedforwardLength + feedbackLength, 1);
weights(delay + 1) = 1;
inverseCorrelation = initial_inverse_correlation(numel(weights), cfg, updateRule);
decisions = zeros(size(reference));
mse = zeros(size(reference));
estimates = zeros(size(reference));
trace = initialize_trace(reference, numel(weights));
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
        decisions(symbolIndex) = sign(real(estimate));
    end
    if decisions(symbolIndex) == 0
        decisions(symbolIndex) = 1;
    end
    error = decisions(symbolIndex) - estimate;
    [weights, inverseCorrelation] = adaptive_update(weights, inverseCorrelation, ...
        input, error, cfg, updateRule);
    if useDpll
        phaseError = imag(feedforwardEstimate * ...
            (conj(decisions(symbolIndex)) - feedbackTerm));
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

function [decisions, mse, estimates, trace] = multichannel_adaptive_dfe(branches, reference, cfg, updateRule)
reference = reference(:).';
feedforwardLength = cfg.feedforwardTaps;
feedbackLength = cfg.feedbackTaps;
delay = min(ceil(feedforwardLength / 3), feedforwardLength - 1);
branchCount = size(branches, 1);
weights = zeros(branchCount * feedforwardLength + feedbackLength, 1);
for branchIndex = 1:branchCount
    weights((branchIndex - 1) * feedforwardLength + delay + 1) = 1 / branchCount;
end
inverseCorrelation = initial_inverse_correlation(numel(weights), cfg, updateRule);
decisions = zeros(size(reference));
mse = zeros(size(reference));
estimates = zeros(size(reference));
feedforwardWeightCount = branchCount * feedforwardLength;
trace = initialize_trace(reference, numel(weights));
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
        decisions(symbolIndex) = sign(real(estimate));
    end
    if decisions(symbolIndex) == 0
        decisions(symbolIndex) = 1;
    end
    error = decisions(symbolIndex) - estimate;
    [weights, inverseCorrelation] = adaptive_update(weights, inverseCorrelation, ...
        input, error, cfg, updateRule);
    mse(symbolIndex) = abs(reference(symbolIndex) - estimate)^2;
    trace.error(symbolIndex) = reference(symbolIndex) - estimate;
    trace.weightNorm(symbolIndex) = norm(weights);
    trace.coefficientHistory(:, symbolIndex) = weights;
end
end

function trace = initialize_trace(reference, weightCount)
trace.feedforwardOutput = zeros(size(reference));
trace.feedbackCancellation = zeros(size(reference));
trace.error = zeros(size(reference));
trace.weightNorm = zeros(size(reference));
trace.coefficientHistory = zeros(weightCount, numel(reference));
trace.phase = zeros(size(reference));
trace.frequency = zeros(size(reference));
end

function inverseCorrelation = initial_inverse_correlation(weightCount, cfg, updateRule)
if updateRule == "rls"
    inverseCorrelation = cfg.rlsInitialInverseCorrelation * eye(weightCount);
else
    inverseCorrelation = [];
end
end

function [weights, inverseCorrelation] = adaptive_update(weights, inverseCorrelation, ...
        input, error, cfg, updateRule)
switch updateRule
    case "lms"
        weights = weights + cfg.lmsStep * input * conj(error);
    case "nlms"
        weights = weights + cfg.nlmsStep * input * conj(error) / ...
            (real(input' * input) + 1e-5);
    case "rls"
        forgettingFactor = cfg.rlsForgettingFactor;
        gain = inverseCorrelation * input / (forgettingFactor + ...
            real(input' * inverseCorrelation * input));
        weights = weights + gain * conj(error);
        inverseCorrelation = (inverseCorrelation - ...
            gain * input' * inverseCorrelation) / forgettingFactor;
        inverseCorrelation = (inverseCorrelation + inverseCorrelation') / 2;
    otherwise
        error("SCFDE:UnknownAdaptiveRule", ...
            "Unknown adaptive update rule: %s", updateRule);
end
end

function output = subband_ptr(input, impulse, bandCount, regularization, branches, branchImpulses)
% Subarray passive time-reversal front end (book 2-48): each branch is
% matched filtered by h_k*(-n) and the subarray outputs are summed.
if nargin < 5 || isempty(branches)
    branches = input(:).';
end
if nargin < 6 || isempty(branchImpulses)
    branchImpulses = impulse(:).';
end
branchCount = size(branches, 1);
if size(branchImpulses, 1) ~= branchCount
    branchImpulses = repmat(impulse(:).', branchCount, 1);
end
output = zeros(1, size(branches, 2));
for branch = 1:branchCount
    timeReversed = conj(fliplr(branchImpulses(branch, :)));
    output = output + filter(timeReversed, 1, branches(branch, :));
end
end
