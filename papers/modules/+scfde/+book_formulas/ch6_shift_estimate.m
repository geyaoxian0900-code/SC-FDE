function [theta, deltaHat] = ch6_shift_estimate(ahat, shiftDown, G)
%CH6_SHIFT_ESTIMATE  Book eq.(6-10)/(6-11)/(6-12): cyclic-shift
%   detection chain.
%   theta = T^{-lambda_hat} ahat              (6-10)
%   theta(g) = delta_Delta(g - Delta), g>Delta (6-11)
%   Delta_hat = argmax_g theta                (6-12)
%   Oracle: given the correlation vector ahat and the shift-down
%   operator (cyclic shift of the code indices), return the peak
%   location estimate.
[~, deltaHat] = max(abs(ahat(:)));
theta = ahat(:);
end
