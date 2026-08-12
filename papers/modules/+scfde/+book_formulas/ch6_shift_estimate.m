function [theta, deltaHat] = ch6_shift_estimate(ahat, G)
%CH6_SHIFT_ESTIMATE  Book eq.(6-10)/(6-11)/(6-12): cyclic-shift
%   detection chain.
%   lambda_hat = argmax_g |ahat(g)| - 1     (shift estimate)
%   theta      = T^{-lambda_hat} ahat       (6-10, actual cyclic shift)
%   theta(g)   = delta_Delta(g - Delta)     (6-11, peak reference)
%   Delta_hat  = argmax_g theta             (6-12, peak position)
%   Oracle: ahat correlation vector (length G); the returned theta has
%   its peak moved to position 1 and Delta_hat = 1 for any input.
if nargin < 2 || isempty(G)
    G = numel(ahat);
end
ahat = ahat(:);
[~, peak] = max(abs(ahat));
lambdaHat = peak - 1;
theta = circshift(ahat, -lambdaHat);      % T^{-lambda_hat} ahat (6-10)
[~, deltaHat] = max(theta);               % (6-12)
end
