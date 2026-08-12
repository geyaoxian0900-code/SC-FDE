function [y, h] = ch1_channel_model(x, taps, delays, noiseSigma)
%CH1_CHANNEL_MODEL  Book eq.(1-9)/(1-10): static-discrete special-case
%   oracle of the linear time-varying channel.
%   y(t) = int h(t,tau) x(t-tau) dtau + n(t)          (1-9)
%   h(t,tau) = sum_p a_p(t) delta(tau - tau_p(t))     (1-10)
%   SPECIAL CASE (ALG-EQUIV): constant a_p and tau_p; the time-varying
%   a_p(t)/tau_p(t) of (1-10) is not implemented here.  The CIR length
%   is max(tau_p)+1 and does NOT grow with the input length.
if nargin < 4 || isempty(noiseSigma)
    noiseSigma = 0;
end
h = zeros(1, max(delays) + 1);
for p = 1:numel(taps)
    h(delays(p) + 1) = h(delays(p) + 1) + taps(p);
end
y = conv(h, x);
if noiseSigma > 0
    y = y + noiseSigma / sqrt(2) * (randn(size(y)) + 1j * randn(size(y)));
end
end
