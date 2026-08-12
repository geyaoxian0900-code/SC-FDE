function output = subband_ptr(input, impulse, bandCount, regularization, branches, branchImpulses)
%SUBBAND_PTR Subarray passive time-reversal front end (book 2-48).
%   y_p(n) = sum_{k in subarray p} h_k*(-n) * r_k(n)   (linear convolution)
%
%   Each branch k is filtered by the time-reversed conjugate of its own
%   channel h_k*(-n) via LINEAR convolution and the subarray outputs are
%   summed (eq. 2-48).  When no branch data is provided, a single-branch
%   PTR is returned (eq. 2-47 form).  Delay alignment: the focused
%   output is windowed to the block length starting at the main tap of
%   the matched filter.
%
%   bandCount and regularization are kept for interface compatibility;
%   the pure PTR of eq. (2-48) involves no inverse filtering, so the
%   regularization is not used.
%   The previous circular (frequency-domain) variant is kept in
%   subband_ptr_circular_engineering.m.
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
blockLength = size(branches, 2);
output = zeros(1, blockLength);
for branch = 1:branchCount
    imp = branchImpulses(branch, :);
    timeReversal = conj(fliplr(imp));
    focusedFull = conv(timeReversal, branches(branch, :));
    % Peak alignment: main tap of h_k*(-n) lands at position L_k
    % (see ptr_dfe for the fliplr-index reasoning).
    Lk = numel(imp);
    output = output + focusedFull(Lk:Lk + blockLength - 1);
end
end
