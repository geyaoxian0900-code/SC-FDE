function s = ch2_modulated_signal(t, u, fc)
%CH2_MODULATED_SIGNAL  Book eq.(2-1)/(2-2): single-carrier passband signal.
%   s(t) = Re{ u(t) e^{j2 pi fc t} }            (2-2)
%         = a(t) cos(2 pi fc t + phi)
%         = s_I(t) cos(2 pi fc t) - s_Q(t) sin(2 pi fc t)   (2-1)
%   u = complex envelope; returns the passband real signal.
s = real(u .* exp(1j * 2 * pi * fc * t));
end
