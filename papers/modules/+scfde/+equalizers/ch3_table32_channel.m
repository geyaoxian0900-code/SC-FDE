function [channel, info] = ch3_table32_channel(sampleRate, fractionalPolicy)
%CH3_TABLE32_CHANNEL Chapter-3 Table 3-2 five-path reference channel
% (book/P68.png, recovered 2026-08-17).
%   [CHANNEL, INFO] = CH3_TABLE32_CHANNEL(SAMPLERATE, FRACTIONALPOLICY)
%
% Locked table values (book Table 3-2, "径/增益/时延"):
%     tap  gain        delay (ms)
%     1    0.5791      0
%     2    0.6929      9.8
%     3    0.3370      16.4
%     4    0.1938      26.0
%     5    0.1831      31.1
%
% The book publishes ONLY the tap gains and delays (milliseconds): no
% phases are given (phaseStatus = "PARAM-UNRECOVERABLE"), so the taps
% are placed with ZERO phase and the raw gains are traced.  The channel
% is normalized to unit energy; the raw gains are recorded in
% INFO.rawGains.
%
% Fractional-delay policy (SILENT ROUNDING IS PROHIBITED):
%   delaySamples = delayMs * 1e-3 * sampleRate.
%   * FRACTIONALPOLICY = "raise" (default): if any delay is not an
%     integer number of samples, raise SCFDE:BookParameterUnavailable -
%     the caller must choose a sampling rate that makes every delay an
%     integer sample count, or provide an explicit fractional-delay
%     method.  NEVER round the delays silently.
%   * FRACTIONALPOLICY = "linear": place each tap with LINEAR
%     interpolation across the two adjacent samples (a validated,
%     explicit fractional-delay method); INFO.fractionalMethod records
%     it.  This is an ENGINEERING choice: the book does not define a
%     sampling rate, so a fractional method is required to run at
%     arbitrary rates.
%
% INFO fields: sampleRate, delayMilliseconds (raw), rawGains (raw),
% delaySamples (exact sample positions used), fractionalMethod
% ("none" | "linear"), phaseStatus ("PARAM-UNRECOVERABLE - book gives no
% phases; zero phase used"), normalization ("unit-energy").
if nargin < 1 || isempty(sampleRate)
    error("SCFDE:InvalidTable32Channel", ...
        "sampleRate is required (Hz) - the book delays are milliseconds.");
end
if ~isscalar(sampleRate) || ~isfinite(sampleRate) || sampleRate <= 0
    error("SCFDE:InvalidTable32Channel", ...
        "sampleRate must be a finite positive scalar in Hz.");
end
if nargin < 2 || isempty(fractionalPolicy)
    fractionalPolicy = "raise";
end
fractionalPolicy = string(fractionalPolicy);
if ~ismember(fractionalPolicy, ["raise", "linear"])
    error("SCFDE:InvalidTable32Channel", ...
        "fractionalPolicy must be 'raise' or 'linear'.");
end
delayMilliseconds = [0, 9.8, 16.4, 26.0, 31.1];
rawGains = [0.5791, 0.6929, 0.3370, 0.1938, 0.1831];
delaySamples = delayMilliseconds * 1e-3 * sampleRate;
isIntegerDelay = all(abs(delaySamples - round(delaySamples)) < 1e-9);
if ~isIntegerDelay && fractionalPolicy == "raise"
    error("SCFDE:BookParameterUnavailable", ...
        "Table 3-2 delays [%s] ms are NOT integer samples at %g Hz; " + ...
        "silent rounding is prohibited - choose an integer-sample rate " + ...
        "or an explicit fractional-delay policy.", ...
        strjoin(string(delayMilliseconds), ", "), sampleRate);
end
maxDelay = max(delaySamples);
channelLength = floor(maxDelay) + 2;   % +2 covers the linear-interp span
channel = complex(zeros(1, channelLength));
if isIntegerDelay
    positions = round(delaySamples);
    channel(positions + 1) = rawGains;
    fractionalMethod = "none";
else
    % Linear fractional-delay placement: tap at d = position + frac,
    % contribution (1-frac)*gain at position, frac*gain at position+1.
    for tap = 1:numel(delaySamples)
        position = floor(delaySamples(tap));
        fraction = delaySamples(tap) - position;
        channel(position + 1) = channel(position + 1) + (1 - fraction) * rawGains(tap);
        channel(position + 2) = channel(position + 2) + fraction * rawGains(tap);
    end
    fractionalMethod = "linear";
end
normEnergy = norm(channel);
if normEnergy <= 0
    error("SCFDE:InvalidTable32Channel", ...
        "the Table 3-2 channel must have nonzero energy.");
end
channel = channel / normEnergy;
info = struct("sampleRate", sampleRate, ...
    "delayMilliseconds", delayMilliseconds, ...
    "rawGains", rawGains, ...
    "delaySamples", delaySamples, ...
    "fractionalMethod", fractionalMethod, ...
    "phaseStatus", "PARAM-UNRECOVERABLE - book gives no phases; zero phase used", ...
    "normalization", "unit-energy");
end