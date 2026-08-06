function [feedforward, feedback] = ch4_fd_ibdfe_weights(Hest, noiseVariance, rho)
%CH4_FD_IBDFE_WEIGHTS Book (4-56)~(4-58) FD-IBDFE coefficients.
denominator = (noiseVariance + abs(Hest).^2) - rho * abs(Hest).^2;
lambda = noiseVariance * sum(1 ./ max(denominator, eps)) / ...
    max(sum((noiseVariance + abs(Hest).^2) ./ max(denominator, eps)), eps);
feedback = (lambda * (noiseVariance + abs(Hest).^2) - noiseVariance) ./ ...
    max(denominator, eps);
feedforward = conj(Hest) .* (1 + feedback) ./ ...
    (noiseVariance + abs(Hest).^2);
end
