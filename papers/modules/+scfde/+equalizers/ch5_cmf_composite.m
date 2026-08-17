function composite = ch5_cmf_composite(channel)
%CH5_CMF_COMPOSITE CMF composite impulse (book (5-41)~(5-45)).
%   COMPOSITE = CH5_CMF_COMPOSITE(CHANNEL)
%
% The channel-matched-filter (CMF) composite impulse is the matched
% filter correlation
%       x = conv(conj(fliplr(channel)), channel)          (5-41)
% whose peak path is aligned to the center and normalized to x_0 = 1
% per (5-45).  By (5-42) the composite response is symmetric around the
% main path (x'_{-i} = x_i), which is exactly the property that turns
% the postcursor ISI of the forward stream into the precursor ISI of the
% time-reversed stream (block time reversal, (5-48)).
%
% The colored CMF noise correlation (5-43) is IGNORED by all later
% detection (explicit book assumption).
%
% The output is a 1 x (2*m+1) row (m = numel(channel)-1) with the
% maximum-path coefficient at the center position, normalized so that
% the center coefficient is exactly 1.
if ~isvector(channel) || isempty(channel) || any(~isfinite(channel))
    error("SCFDE:InvalidCmfChannel", ...
        "channel must be a finite non-empty vector.");
end
channel = channel(:).';
correlation = conv(conj(fliplr(channel)), channel);
center = ceil(numel(correlation) / 2);
[~, peak] = max(abs(correlation));
shift = peak - center;
if shift > 0
    aligned = [correlation(1 + shift:end), zeros(1, shift)];
elseif shift < 0
    aligned = [zeros(1, -shift), correlation(1:end + shift)];
else
    aligned = correlation;
end
if abs(aligned(center)) <= eps
    error("SCFDE:InvalidCmfChannel", ...
        "the composite impulse peak must be nonzero.");
end
composite = aligned / aligned(center);
end