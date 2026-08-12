function a = ch1_thorp_absorption(f)
%CH1_THORP_ABSORPTION  Book eq.(1-4): Thorp absorption coefficient.
%   10 lg a(f) = 0.11 f^2/(1+f^2) + 44 f^2/(4100+f^2) + 2.75e-4 f^2 + 0.003
%   f [kHz]; returns 10*log10(a) in dB/km.
a = 0.11 * f .^ 2 ./ (1 + f .^ 2) + 44 * f .^ 2 ./ (4100 + f .^ 2) + ...
    2.75e-4 * f .^ 2 + 0.003;
end
