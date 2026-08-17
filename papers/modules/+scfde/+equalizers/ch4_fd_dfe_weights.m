function [feedforward, feedback, lambda] = ch4_fd_dfe_weights(H, rho, noiseVariance)
%CH4_FD_DFE_WEIGHTS Strict FD-DFE / FD-Turbo coefficients
% (book (4-55)~(4-58), recovered from book/P90.png, 2026-08-17):
%   D_k       = sigma^2 + |h_k|^2 - rho*|h_k|^2
%   lambda    = sigma^2 * sum_k(1/D_k)
%               / sum_k((sigma^2+|h_k|^2)/D_k)            (4-58)
%   b_k       = [lambda*(sigma^2+|h_k|^2) - sigma^2] / D_k (4-57)
%   w_k       = conj(h_k)*(1+b_k) / (sigma^2+|h_k|^2)      (4-56)
% with rho = E[|x_hat|^2] (4-55) the feedback reliability.
%
% The zero-sum constraint sum_k b_k = 0 follows from (4-58)
% ALGEBRAICALLY (lambda is chosen exactly so the sum vanishes); it is
% asserted numerically with a scale-aware tolerance and is NEVER enforced
% by a B - mean(B) projection.
%
% Inputs are NOT floored: nonfinite input, rho outside [0,1], or any
% D_k <= 0 raise SCFDE:InvalidDfeWeights instead of silently flooring
% the formula.
if ~isvector(H) || numel(H) < 2
    error("SCFDE:InvalidDfeWeights", "H must be a vector of at least 2 bins.");
end
if ~isscalar(rho) || ~isfinite(rho) || rho < 0 || rho > 1
    error("SCFDE:InvalidDfeWeights", "rho must be a scalar in [0,1].");
end
if ~isscalar(noiseVariance) || ~isfinite(noiseVariance) || noiseVariance < 0
    error("SCFDE:InvalidDfeWeights", ...
        "noiseVariance must be a finite non-negative scalar.");
end
H = H(:).';
if any(~isfinite(H))
    error("SCFDE:InvalidDfeWeights", "H must be finite.");
end
absH2 = abs(H).^2;
A = noiseVariance + absH2;
D = A - rho * absH2;
if any(D <= 0) || any(~isfinite(D))
    error("SCFDE:InvalidDfeWeights", ...
        "D_k = sigma^2 + (1-rho)|h_k|^2 must be strictly positive for every bin.");
end
lambda = noiseVariance * sum(1 ./ D) / sum(A ./ D);
feedback = (lambda * A - noiseVariance) ./ D;
feedforward = conj(H) .* (1 + feedback) ./ A;
% Formula-derived zero-sum invariant (4-58): assert, never project.
scale = max(sum(abs(feedback)), 1);
if abs(sum(feedback)) > 1e-9 * scale
    error("SCFDE:InvalidDfeWeights", ...
        "the (4-58) lambda must impose sum_k b_k = 0 (invariant violated).");
end
end
