function r = ch2_received_continuous(d, h, delays, fd, Ts, w)
%CH2_RECEIVED_CONTINUOUS  Book eq.(2-4): continuous multipath receive.
%   r(t) = sum_l d_l h(t - tau_l) e^{j 2 pi fd t} + w(t)
%   d: symbols, h: pulse/channel waveform, delays: path delays in
%   samples, fd: Doppler shift, Ts: symbol period, w: noise.
%   Discrete oracle of the continuous form (the Doppler exponential
%   lives here, in eq. (2-4), not in the sampled model (2-5)).
if nargin < 5 || isempty(Ts), Ts = 1; end
if nargin < 6 || isempty(w), w = zeros(size(d)); end
hfull = zeros(1, numel(h) + max(delays));
for p = 1:numel(delays)
    hfull(delays(p) + 1:delays(p) + numel(h)) = ...
        hfull(delays(p) + 1:delays(p) + numel(h)) + h;
end
n = 0:numel(d) - 1;
r = conv(d, hfull) .* [exp(1j * 2 * pi * fd * Ts * n), ...
    zeros(1, numel(hfull) - 1)];
r = r(1:numel(d)) + w(:).';
end
