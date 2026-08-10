function output = subband_ptr(input, impulse, bandCount, regularization, branches, branchImpulses)
%SUBBAND_PTR Subarray passive time-reversal front end (book 2-48).
%   y_p(n) = sum_{k in subarray p} h_k*(-n) * r_k(n)
%
% Each branch k is filtered by the time-reversed conjugate of its own
% channel h_k*(-n) and the subarray outputs are summed.  When no branch
% data is provided, a single-branch PTR is returned (Eq. 2-47 form).
%
% bandCount and regularization are kept for interface compatibility; the
% pure PTR of Eq. (2-48) involves no inverse filtering, so the
% regularization is not used.
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
blockLength = size(branches, 2);
for branch = 1:branchCount
    % Circular (frequency-domain) time reversal: the received block is
    % a circular convolution, so the linear filter would spread the
    % focused energy; the circular matched filter yields one
    % correlation peak per symbol (see ptr_dfe).
    branchSpectrum = fft(branchImpulses(branch, :), blockLength);
    output = output + ifft(conj(branchSpectrum) .* ...
        fft(branches(branch, :)));
end
end
