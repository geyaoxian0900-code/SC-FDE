function r = ch2_received_model(d, h, theta, fd, Ts, w)
%CH2_RECEIVED_MODEL  Book eq.(2-4)/(2-5): discrete received signal.
%   r(t) = sum_l d_l h(t - tau_l) e^{j2 pi fd t} + w(t)      (2-4)
%   r_k  = e^{j theta} A_k + e^{j phi} sum_m d_m h_{k-m} + w_k (2-5)
%   Discrete oracle: d symbol sequence, h channel impulse (delay 0 in
%   the first tap), theta constant phase, fd Doppler shift, Ts symbol
%   period, w additive noise (default zero).
if nargin < 6 || isempty(Ts), Ts = 1; end
if nargin < 7 || isempty(w), w = zeros(size(d)); end
n = 0:numel(d) - 1;
doppler = exp(1j * 2 * pi * fd * Ts * n);
r = exp(1j * theta) .* conv(d, h) .* [doppler, zeros(1, numel(h) - 1)];
r = r(1:numel(d)) + w;
end
