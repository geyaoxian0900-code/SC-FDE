function Hnew = ch3_channel_estimate_fuse(H0, HDft, sigma0Squared, sigmaDftSquared)
%CH3_CHANNEL_ESTIMATE_FUSE Exact (3-92) channel-estimate fusion
% (book/P68.png, recovered 2026-08-17):
%   Hnew = (H0 * sigma0^2 + HDft * sigmaDft^2)
%          / (sigma0^2 + sigmaDft^2)
% i.e. EACH branch is weighted by ITS OWN variance (the previous
% production used the cross-weight ordering sigmaDft^2*H0 + sigma0^2*HDft,
% which the recovered scan rejects).
%
% The helper does NOT compute the variances: sigma0Squared and
% sigmaDftSquared are INPUTS (scalars or per-bin vectors).  Invalid
% inputs - negative, nonfinite, or jointly zero variances - raise
% SCFDE:InvalidFusionInput instead of flooring the formula.  Which
% variance VALUES to use is a policy decision of the caller (strict-
% explicit source variances vs engineering-residual estimates); this
% helper never labels an implicit default as BOOK.
if ~isvector(H0) || ~isvector(HDft) || numel(H0) ~= numel(HDft)
    error("SCFDE:InvalidFusionInput", ...
        "H0 and HDft must be equal-length vectors.");
end
if ~isscalar(sigma0Squared) && (~isvector(sigma0Squared) || ...
        numel(sigma0Squared) ~= numel(H0))
    error("SCFDE:InvalidFusionInput", ...
        "sigma0Squared must be a scalar or a per-bin vector.");
end
if ~isscalar(sigmaDftSquared) && (~isvector(sigmaDftSquared) || ...
        numel(sigmaDftSquared) ~= numel(H0))
    error("SCFDE:InvalidFusionInput", ...
        "sigmaDftSquared must be a scalar or a per-bin vector.");
end
H0 = H0(:).';
HDft = HDft(:).';
if ~isscalar(sigma0Squared)
    sigma0Squared = sigma0Squared(:).';
end
if ~isscalar(sigmaDftSquared)
    sigmaDftSquared = sigmaDftSquared(:).';
end
if any(~isfinite(H0)) || any(~isfinite(HDft)) || ...
        any(~isfinite(sigma0Squared)) || any(~isfinite(sigmaDftSquared)) || ...
        any(sigma0Squared < 0) || any(sigmaDftSquared < 0)
    error("SCFDE:InvalidFusionInput", ...
        "estimates must be finite and variances finite non-negative.");
end
denominator = sigma0Squared + sigmaDftSquared;
if any(denominator <= 0)
    error("SCFDE:InvalidFusionInput", ...
        "the (3-92) denominator sigma0^2+sigmaDft^2 must be strictly positive.");
end
Hnew = (H0 .* sigma0Squared + HDft .* sigmaDftSquared) ./ denominator;
end
