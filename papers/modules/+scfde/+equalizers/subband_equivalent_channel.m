function equivalent = subband_equivalent_channel(impulse, branchImpulses)
%SUBBAND_EQUIVALENT_CHANNEL Equivalent channel of the subarray PTR front end.
%   g_p = sum_k h_k*(-n) * h_k   (book 2-48)
%
% Each branch contributes its own autocorrelation; cross-branch terms are
% not part of the matched-filtered subarray combination.  When no branch
% data is provided, the single-branch autocorrelation is returned, which
% is consistent with the single-branch PTR front end (Eq. 2-47 form).
%
% The branch handling mirrors subband_ptr: missing or mismatched
% branchImpulses fall back to the aggregate impulse replicated per branch.
if nargin < 2 || isempty(branchImpulses)
    branchImpulses = impulse(:).';
end
branchCount = size(branchImpulses, 1);
impulseLength = size(branchImpulses, 2);
equivalent = zeros(1, 2 * impulseLength - 1);
for branch = 1:branchCount
    timeReversed = conj(fliplr(branchImpulses(branch, :)));
    equivalent = equivalent + conv(timeReversed, branchImpulses(branch, :));
end
end
