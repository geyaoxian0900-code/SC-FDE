function [Phi, lambda] = ch3_phase_approx(N, theta)
%CH3_PHASE_APPROX  Book eq.(3-39)~(3-41): Doppler phase matrix -> scalar.
%   Phi = F D F^H is circulant; off-diagonals are negligible so
%   Phi ~= lambda I with
%   lambda = Phi(n,n) = (1/N) sum_{p=0}^{N-1} e^{j theta_p}.
F = dft_matrix_book(N);
D = scfde.book_formulas.ch3_doppler_matrix(theta);
Phi = F * D * F' / N;              % circulant (normalized DFT pair)
lambda = mean(exp(1j * theta(:)));
end

function F = dft_matrix_book(N)
n = (0:N - 1).';
k = 0:N - 1;
F = exp(-1j * 2 * pi * (k .* n) / N);
end
