function [etaCp, etaUw] = ch3_spectral_efficiency(N, M, P)
%CH3_SPECTRAL_EFFICIENCY  Book eq.(3-27)/(3-28).
%   eta_CP-SC = N/(N+M);   eta_UW-SC = (N-P)/(N+M)
%   N block length, M CP length, P pilot length.
etaCp = N / (N + M);
etaUw = (N - P) / (N + M);
end
