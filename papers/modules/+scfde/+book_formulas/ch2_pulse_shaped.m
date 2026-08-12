function u = ch2_pulse_shaped(a, g, T, t)
%CH2_PULSE_SHAPED  Book eq.(2-3): complex envelope of the pulse-shaped
%   symbol stream:  u(t) = sum_n a(n) g(t - nT).
%   a: symbol sequence, g: pulse, T: symbol period, t: sample times.
u = zeros(size(t));
for n = 1:numel(a)
    u = u + a(n) * g(t - (n - 1) * T);
end
end
