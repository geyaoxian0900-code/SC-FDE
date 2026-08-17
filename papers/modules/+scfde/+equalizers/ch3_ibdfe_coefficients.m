function [feedforward, feedback, lambda, gamma] = ...
        ch3_ibdfe_coefficients(H, Sigma, noiseVariance, fftSize)
%CH3_IBDFE_COEFFICIENTS Exact IBDFE feedforward/feedback coefficients
% (book (3-86)/(3-87), recovered from book/P67.png, 2026-08-17):
%   Lambda_k = conj(H_k) * Sigma_k
%              / (|H_k|^2 * Sigma_k + N * sigma_w^2)      (3-86)
%   Gamma    = mean_k Lambda_k * H_k                       (3-87)
%   C_k      = Lambda_k / Gamma
%   B_k      = C_k * H_k - 1
% where N = fftSize (the DFT length) and Sigma is the per-bin symbol
% variance.  The N*sigma_w^2 term is REQUIRED by the recovered scan; the
% previous production denominator without N is rejected by the oracle.
%
% Inputs are NOT floored: invalid denominators, zero/nonfinite Gamma and
% malformed inputs raise SCFDE:InvalidCoefficientDenominator instead of
% silently flooring the formula.  Sigma may be a scalar (iteration-level
% symbol variance, broadcast over all bins) or a per-bin vector.
if ~isvector(H)
    error("SCFDE:InvalidCoefficientInput", ...
        "H must be a vector.");
end
if ~isscalar(Sigma) && (~isvector(Sigma) || numel(Sigma) ~= numel(H))
    error("SCFDE:InvalidCoefficientInput", ...
        "Sigma must be a scalar or a vector with one entry per H bin.");
end
if ~isscalar(noiseVariance) || ~isnumeric(noiseVariance) || ...
        ~isfinite(noiseVariance) || noiseVariance < 0
    error("SCFDE:InvalidCoefficientInput", ...
        "noiseVariance must be a finite non-negative scalar.");
end
if ~isscalar(fftSize) || ~isfinite(fftSize) || fftSize <= 0
    error("SCFDE:InvalidCoefficientInput", ...
        "fftSize must be a positive finite scalar.");
end
H = H(:).';
if ~isscalar(Sigma)
    Sigma = Sigma(:).';
end
if any(~isfinite(H)) || any(~isfinite(Sigma)) || any(Sigma < 0)
    error("SCFDE:InvalidCoefficientInput", ...
        "H and Sigma must be finite; Sigma must be non-negative.");
end
denominator = abs(H).^2 .* Sigma + fftSize * noiseVariance;
if any(denominator <= 0) || any(~isfinite(denominator))
    error("SCFDE:InvalidCoefficientDenominator", ...
        "the (3-86) denominator must be strictly positive and finite.");
end
lambda = conj(H) .* Sigma ./ denominator;
gamma = mean(lambda .* H);
if ~isfinite(gamma) || gamma == 0
    error("SCFDE:InvalidCoefficientDenominator", ...
        "the (3-87) Gamma normalization must be finite and nonzero.");
end
feedforward = lambda ./ gamma;
feedback = feedforward .* H - 1;
end
