function [T, corr] = ch6_shift_matrix(c, m)
%CH6_SHIFT_MATRIX  Book eq.(6-4)/(6-5): cyclic shift matrix and
%   orthogonality:  T = [0_{1x(M-1)} 1; I_{M-1} 0],  c^T T^m c =
%   M if m mod M == 0 else 1 (unit-amplitude spreading sequence).
M = numel(c);
T = circshift(eye(M), 1, 1);   % book eq.(6-4): T e_1 = e_2, T^M = I
corr = zeros(size(m));
for i = 1:numel(m)
    corr(i) = c.' * (T ^ m(i)) * c;
end
end
