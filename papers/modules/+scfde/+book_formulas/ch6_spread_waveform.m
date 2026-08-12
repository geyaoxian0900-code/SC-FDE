function c = ch6_spread_waveform(C, phi, Tc)
%CH6_SPREAD_WAVEFORM  Book eq.(6-13): spreading waveform.
%   c_i(t) = sum_k C_{i,k} phi(t - k T_c)
%   C: chip sequence (1 x K), phi: shaping pulse, Tc: chip duration.
t = (0:numel(phi) - 1) * Tc;
c = zeros(size(t));
for k = 1:numel(C)
    c = c + C(k) * phi(max(1, min(numel(phi), ...
        round(t / Tc) - (k - 1) + 1)));
end
end
