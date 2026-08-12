function [rDsss, rM] = ch6_spreading_rate(L, Tc, M)
%CH6_SPREADING_RATE  Book eq.(6-2)/(6-3): data rates.
%   R_DSSS = 1/(L T_c);  R_M = log2(M)/(L T_c)
%   L spreading length, T_c chip duration, M alphabet size.
rDsss = 1 ./ (L .* Tc);
if nargin >= 3
    rM = log2(M) ./ (L .* Tc);
else
    rM = NaN;
end
end
