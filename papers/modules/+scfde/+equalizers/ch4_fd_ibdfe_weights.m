function [feedforward, feedback] = ch4_fd_ibdfe_weights(Hest, noiseVariance, rho)
%CH4_FD_IBDFE_WEIGHTS Book (4-56)~(4-58) FD-IBDFE coefficients.
%   The numerator/denominator of (4-57)/(4-58) remain
%   BLOCKED-SOURCE-REVIEW pending the book/21.png double review; the
%   construction below is the current production form kept for those
%   coefficients.  The zero-mean constraint sum_k b_k = 0 (spec 4.2) is
%   ENFORCED explicitly.
denominator = (noiseVariance + abs(Hest).^2) - rho * abs(Hest).^2;
lambda = noiseVariance * sum(1 ./ max(denominator, eps)) / ...
    max(sum((noiseVariance + abs(Hest).^2) ./ max(denominator, eps)), eps);
feedback = (lambda * (noiseVariance + abs(Hest).^2) - noiseVariance) ./ ...
    max(denominator, eps);
feedback = feedback - mean(feedback);   % (4-52): sum_k b_k = 0
feedforward = conj(Hest) .* (1 + feedback) ./ ...
    (noiseVariance + abs(Hest).^2);
end
