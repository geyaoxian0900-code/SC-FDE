function [decisions, mse, estimates, trace] = known_dfe_core(received, reference, impulse, cfg)
%KNOWN_DFE_CORE Shared known-channel DFE implementation for the equalizer package.
% Feedforward weights solve the strict MMSE problem
%   w = argmin E|w'*r - x|^2  =>  w = (C'C + sigma_w^2/sigma_x^2 * I)^-1 C' e_d
% where C is the channel convolution matrix, sigma_x^2 = 1 (unit-energy
% QPSK) and sigma_w^2 = 10^(-snrDb/10) * P_rx, with P_rx the average
% received power so that the noise covariance is derived from the actual
% signal and noise variances rather than an empirical constant.
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
% Noise variance: noiseRatio is relative to unit signal variance; scale
% by the received power so the regularization matches the actual
% noise-to-signal ratio at the equalizer input.
signalPower = mean(abs(received(1:min(numel(received), ...
    max(feedforwardLength, numel(reference))))).^2);
noisePower = signalPower * 10^(-cfg.snrDb / 10);
noiseVariance = noisePower / max(signalPower, eps);
weights = (channelMatrix' * channelMatrix + ...
    noiseVariance * eye(feedforwardLength)) \ ...
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
