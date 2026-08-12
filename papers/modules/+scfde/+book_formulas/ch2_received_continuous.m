function r = ch2_received_continuous(d, h, tau, theta, w)
%CH2_RECEIVED_CONTINUOUS  Book eq.(2-4): continuous received signal,
%   FULL SUPPORT oracle (no silent tail truncation).
%   r'(t) = sum_n d_n h(t - nT - tau) e^{j theta} + w(t)
%   d: symbol sequence, h: generalized channel impulse response,
%   tau: fixed propagation delay (samples), theta: fixed carrier phase.
%   Output length = numel(d) + numel(h) + tau - 1; noise, when given,
%   must span the full support.
d = d(:).';
h = h(:).';
hDelayed = [zeros(1, tau), h];
signal = exp(1j * theta) .* conv(d, hDelayed);
if nargin < 5 || isempty(w)
    w = zeros(size(signal));
else
    w = w(:).';
    assert(numel(w) == numel(signal), "SCFDE:BookNoiseLength", ...
        "Noise must span the full received support (%d samples).", ...
        numel(signal));
end
r = signal + w;
end
