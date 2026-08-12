function output = subband_ptr_circular_engineering(input, impulse, bandCount, regularization, branches, branchImpulses)
%SUBBAND_PTR_CIRCULAR_ENGINEERING Circular subarray passive time reversal.
%   ENGINEERING variant (BOOK_CONVENTIONS.md rule 2): the book defines
%   the linear filter y_p(n) = sum_k h_k*(-n) * r_k(n) (eq. 2-48); the
%   circular frequency-domain form below is an engineering substitute
%   for block-circulant frames.  The book path is subband_ptr.m.
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
    branchSpectrum = fft(branchImpulses(branch, :), blockLength);
    output = output + ifft(conj(branchSpectrum) .* ...
        fft(branches(branch, :)));
end
end
