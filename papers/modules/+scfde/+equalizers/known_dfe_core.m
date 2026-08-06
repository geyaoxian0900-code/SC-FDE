function [decisions, mse, estimates, trace] = known_dfe_core(received, reference, impulse, cfg)
%KNOWN_DFE_CORE Shared known-channel DFE implementation for the equalizer package.
received = received(:).';
reference = reference(:).';
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
        decisions(symbolIndex) = scfde.equalizers.slice_decision(estimate, cfg);
    end
    mse(symbolIndex) = abs(estimate - reference(symbolIndex))^2;
    trace.error(symbolIndex) = reference(symbolIndex) - estimate;
end
end
