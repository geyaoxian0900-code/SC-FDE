function theta = ch6_shift_relation(thetaA, delta)
%CH6_SHIFT_RELATION  Book eq.(6-10): cyclic-shift analysis relation.
%   theta = T^{-Delta} theta_a
%   thetaA: spreading-sequence autocorrelation (peak at position 1 for
%   Delta = 0); Delta: the TRANSMITTED cyclic shift.  The detector must
%   NOT pre-align the peak (that would make the estimate identically 1).
theta = circshift(thetaA(:), delta);
end
