function D = ch3_doppler_matrix(theta)
%CH3_DOPPLER_MATRIX  Book eq.(3-37): residual-Doppler phase matrix.
%   D = diag[ e^{j theta_0} ... e^{j theta_{N-1}} ]
%   with theta_k = 2 pi k f_s T_s (residual Doppler phase per sample).
D = diag(exp(1j * theta(:)));
end
