function thetaA = ch6_sequence_autocorrelation(a, G)
%CH6_SEQUENCE_AUTOCORRELATION  Book eq.(6-7): spreading-sequence
%   autocorrelation.
%   theta_a = (1/G) Re{ F^{-1}[ (F a)^* .* (F a) ] }
%   a: spreading sequence (length G); F: forward DFT (no 1/N).
a = a(:);
thetaA = (1 / G) * real(ifft(conj(fft(a)) .* fft(a)));
end
