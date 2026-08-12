function r = ch2_received_model(d, h, theta, w)
%CH2_RECEIVED_MODEL  Book eq.(2-5): sampled received signal,
%   FULL SUPPORT oracle (no silent tail truncation).
%   r_k = e^{j theta} sum_l d_l h_{k-l} + w_k
%   (current symbol + ISI + AWGN decomposition:
%    r_k = e^{j theta} d_k h_0 + e^{j theta} sum_{l~=k} d_l h_{k-l} + w_k)
%   Output length = numel(d) + numel(h) - 1; noise, when given, must
%   span the full support.  The time-varying Doppler exponential belongs
%   to the continuous model (2-4) only, not here.
d = d(:).';
h = h(:).';
signal = exp(1j * theta) .* conv(d, h);
if nargin < 4 || isempty(w)
    w = zeros(size(signal));
else
    w = w(:).';
    assert(numel(w) == numel(signal), "SCFDE:BookNoiseLength", ...
        "Noise must span the full received support (%d samples).", ...
        numel(signal));
end
r = signal + w;
end
