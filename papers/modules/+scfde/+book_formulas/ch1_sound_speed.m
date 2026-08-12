function c = ch1_sound_speed(t, S, H)
%CH1_SOUND_SPEED  Book eq.(1-1): seawater sound speed.
%   c = 1449.2 + 4.6t - 0.055t^2 + 0.00029t^3 + (1.34-0.01t)(S-35) + 0.016H
%   t [C], S [per-mille], H [m].
c = 1449.2 + 4.6 * t - 0.055 * t .^ 2 + 0.00029 * t .^ 3 + ...
    (1.34 - 0.01 * t) .* (S - 35) + 0.016 * H;
end
