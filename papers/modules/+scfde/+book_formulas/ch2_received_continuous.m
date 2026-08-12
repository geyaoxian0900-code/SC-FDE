function r = ch2_received_continuous(d, h, tau, theta, w)
%CH2_RECEIVED_CONTINUOUS  Book eq.(2-4): continuous received signal.
%   r'(t) = sum_n d_n h(t - nT - tau) e^{j theta} + w(t)
%   d: symbol sequence, h: generalized channel impulse response,
%   tau: fixed propagation delay, theta: fixed carrier phase, w: noise.
%   Discrete oracle: r_k = e^{j theta} sum_n d_n h_{k-n-tau} + w_k.
%   NOTE: the book has NO Doppler exponential in (2-4); the fixed
%   phase e^{j theta} is the only carrier term (book/5.png page 18,
%   verified 2026-08-12).
if nargin < 5 || isempty(w)
    w = zeros(size(d));
end
hfull = [zeros(1, tau), h(:).'];
r = exp(1j * theta) .* conv(d(:).', hfull);
r = r(1:numel(d)) + w(:).';
end
