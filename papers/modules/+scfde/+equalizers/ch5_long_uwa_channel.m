function channel = ch5_long_uwa_channel(delays, power, phase)
%CH5_LONG_UWA_CHANNEL Chapter-5 long underwater acoustic channel.
%   CHANNEL = CH5_LONG_UWA_CHANNEL() uses the project's synthetic
%   11-tap model (delays 0..15 symbols, exponential power decay, fixed
%   phases).  The book chapter 5 only mentions a "3 km channel model"
%   without publishing the per-tap parameters, so this is a synthetic
%   reconstruction; the per-tap parameters are exposed for sensitivity
%   analysis:
%     CH5_LONG_UWA_CHANNEL(DELAYS, POWER, PHASE) uses the given taps.
%   channel = sum_k sqrt(power_k) * exp(j*phase_k) at delay delays_k,
%   normalized to unit energy.
%
%   Tap parameters (project synthesis, not from the book):
%     delays = [0 1 2 3 4 5 7 9 11 13 15] symbols
%     power  = exp(-delays/5.5)
%     phase  = [0 .5 -1.0 .8 -2.1 .25 -1.5 1.4 -.8 .9 -2.6] rad
if nargin < 1 || isempty(delays)
    delays = [0, 1, 2, 3, 4, 5, 7, 9, 11, 13, 15];
end
if nargin < 2 || isempty(power)
    power = exp(-delays / 5.5);
end
if nargin < 3 || isempty(phase)
    phase = [0, .5, -1.0, .8, -2.1, .25, -1.5, 1.4, -.8, .9, -2.6];
    if numel(phase) < numel(delays)
        phase = [phase, zeros(1, numel(delays) - numel(phase))];
    end
end
% Input validation: integer, non-negative, unique delays; non-negative
% power with the same length as delays; phase with the same length.
assert(isvector(delays) && all(delays == round(delays)) && ...
    all(delays >= 0) && numel(unique(delays)) == numel(delays), ...
    "SCFDE:Channel", "delays must be unique non-negative integers");
assert(numel(power) == numel(delays) && all(power >= 0), ...
    "SCFDE:Channel", "power must be non-negative with one value per delay");
assert(numel(phase) == numel(delays), ...
    "SCFDE:Channel", "phase must have one value per delay");
channel = zeros(1, delays(end) + 1);
channel(delays + 1) = sqrt(power) .* exp(1j * phase);
channel = channel / norm(channel);
end
