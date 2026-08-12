function C = ch3_mmse_matrix(H, Phi, sigma2)
%CH3_MMSE_MATRIX  Book eq.(3-42)~(3-44): frequency-domain MMSE matrix
%   solution with residual Doppler.
%   C = (H^H Phi^H Phi H + sigma^2 I)^-1 H^H Phi^H
%   where H = diag(H_k) is the diagonal channel (per-bin equalizer).
C = (H' * Phi' * Phi * H + sigma2 * eye(size(H, 1))) \ (H' * Phi');
end
