function equivalent = subband_equivalent_channel(impulse, branchImpulses, branchCount)
%SUBBAND_EQUIVALENT_CHANNEL Equivalent channel of the subarray PTR front end.
%   g_p = sum_k h_k*(-n) * h_k   (book 2-48)
%
% Each branch contributes its own autocorrelation; cross-branch terms are
% not part of the matched-filtered subarray combination.  When no branch
% data is provided, the aggregate impulse is replicated branchCount times
% (the same fallback as the subband_ptr front end), so the equivalent
% channel always matches the number of branches used at the front end.
%
% The branch handling mirrors subband_ptr: missing or mismatched
% branchImpulses fall back to the aggregate impulse replicated per branch.
if nargin < 3 || isempty(branchCount)
    branchCount = 1;
end
if nargin < 2 || isempty(branchImpulses)
    branchImpulses = repmat(impulse(:).', branchCount, 1);
elseif size(branchImpulses, 1) ~= branchCount
    branchImpulses = repmat(impulse(:).', branchCount, 1);
end
impulseLength = size(branchImpulses, 2);
equivalent = zeros(1, 2 * impulseLength - 1);
for branch = 1:branchCount
    timeReversed = conj(fliplr(branchImpulses(branch, :)));
    equivalent = equivalent + conv(timeReversed, branchImpulses(branch, :));
end
end
