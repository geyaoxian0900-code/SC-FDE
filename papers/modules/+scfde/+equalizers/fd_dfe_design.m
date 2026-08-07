function [W, feedback] = fd_dfe_design(H, noiseRatio, feedbackLength)
%FD_DFE_DESIGN FD-DFE coefficients per the book's MMSE derivation
% (Eqs. 4-10..4-18).  The feedforward filter carries the
% frequency-dependent feedback polynomial
%   F_k = 1 + sum_{m=1}^B f_m e^{-j*2*pi*k*m/N}
% (f_1 sits at delay m = 1, so the feedback vector is zero-padded before
% the FFT), and the time-domain feedback loop subtracts
%   sum_m f_m xhat_{n-m}
% from the feedforward output.  The feedback coefficients solve the
% self-consistent system
%   q(n)   = 1/N * sum_k |H_k|^2/(|H_k|^2+sigma^2) * exp(j*2*pi*k*n/N)
%   V(m,n) = q(m-n mod N)      (circular feedback correlation matrix)
%   v(m)   = q(m)              (post-cursor ISI vector, m=1..B)
%   (V - I) f = -v
% so that the shaped post-cursor g(m) = f_m for m = 1..B and the
% feedback cancellation removes it exactly.
N = numel(H);
if feedbackLength == 0
    feedback = zeros(0, 1);
    W = conj(H) ./ (abs(H).^2 + noiseRatio);
    return;
end
gamma = abs(H).^2 ./ (abs(H).^2 + noiseRatio);
q = ifft(gamma); % complex (H is not even-symmetric in general)
V = zeros(feedbackLength, feedbackLength);
for m = 1:feedbackLength
    for n = 1:feedbackLength
        V(m, n) = q(mod(m - n, N) + 1);
    end
end
v = q(2:feedbackLength + 1);
feedback = -(V - eye(feedbackLength)) \ v;
feedback = feedback(:);
Fk = 1 + fft([0; feedback], N); % f_1 at delay m = 1
Fk = Fk(:);
W = conj(H) ./ (abs(H).^2 + noiseRatio) .* Fk;
end
