function [theta, deltaHat] = ch6_shift_estimate(thetaA, Delta, G)
%CH6_SHIFT_ESTIMATE  Book eq.(6-10)/(6-12): cyclic-shift detection.
%   theta   = T^{-Delta} theta_a        (6-10)
%   Delta_hat = argmax_g theta(g)        (6-12)
%   thetaA : the spreading-sequence autocorrelation vector (6-7), peak
%            at position 1 for Delta = 0;
%   Delta  : the TRANSMITTED cyclic shift applied by the CSK modulator;
%   G      : sequence length (default numel(thetaA)).
%   The oracle builds theta from the KNOWN transmitted shift and then
%   recovers Delta_hat = argmax theta (MATLAB 1-based: peak-1).
%   This is the analysis relation of (6-10): sending shift Delta moves
%   the autocorrelation peak by Delta; the detector must NOT pre-align
%   the peak (that would make Delta_hat identically 1).
if nargin < 3 || isempty(G)
    G = numel(thetaA);
end
thetaA = thetaA(:);
theta = circshift(thetaA, Delta);       % T^{-Delta} theta_a (6-10)
[~, peak] = max(theta);                 % 1-based peak position
deltaHat = peak - 1;                    % (6-12), mapped to shift units
end
