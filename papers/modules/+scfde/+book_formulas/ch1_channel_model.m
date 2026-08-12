function [y, h] = ch1_channel_model(x, taps, delays, noiseSigma)
%CH1_CHANNEL_MODEL  Book eq.(1-9)/(1-10): linear time-varying channel.
%   y(t) = int h(t,tau) x(t-tau) dtau + n(t)          (1-9)
%   h(t,tau) = sum_p a_p(t) delta(tau - tau_p(t))     (1-10)
%   Discrete oracle: taps = [a_1 ... a_P] (complex gains),
%   delays = [tau_1 ... tau_P] (integer sample delays).
%   Returns the multipath output (linear convolution) plus noise.
if nargin < 4 || isempty(noiseSigma)
    noiseSigma = 0;
end
h = zeros(1, numel(x) + max(delays));
for p = 1:numel(taps)
    h(delays(p) + 1) = h(delays(p) + 1) + taps(p);
end
y = conv(h, x);
if noiseSigma > 0
    y = y + noiseSigma / sqrt(2) * (randn(size(y)) + 1j * randn(size(y)));
end
end
