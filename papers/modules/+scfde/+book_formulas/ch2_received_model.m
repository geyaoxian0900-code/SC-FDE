function r = ch2_received_model(d, h, theta, w)
%CH2_RECEIVED_MODEL  Book eq.(2-5): sampled received signal.
%   r_k = e^{j theta} sum_l d_l h_{k-l} + w_k
%       = e^{j theta} d_k h_0
%         + e^{j theta} sum_{l ~= k} d_l h_{k-l} + w_k   (current symbol
%                                                         + ISI + AWGN)
%   d: transmitted symbols, h: channel impulse (h_0 = first tap),
%   theta: carrier phase, w: additive noise (default zero).
%   The time-varying Doppler exponential belongs to the continuous
%   model (2-4), not to (2-5); it is NOT applied here.
if nargin < 4 || isempty(w)
    w = zeros(size(d));
end
r = exp(1j * theta) .* conv(d(:).', h(:).');
r = r(1:numel(d)) + w(:).';
end
