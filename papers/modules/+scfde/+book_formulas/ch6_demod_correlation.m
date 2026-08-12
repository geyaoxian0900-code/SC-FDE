function theta = ch6_demod_correlation(shat, a, G)
%CH6_DEMOD_CORRELATION  Book eq.(6-9): CSK demodulator correlation.
%   theta = (1/G) Re{ F^{-1}[ (F shat)^* .* (F a) ] }
%   shat: received/reconstructed chip sequence, a: reference spreading
%   sequence (length G).  NOTE the conjugation is on F*shat (the
%   received side), opposite to the engineering correlator which
%   conjugated the reference (F a)*.
shat = shat(:);
a = a(:);
theta = (1 / G) * real(ifft(conj(fft(shat)) .* fft(a)));
end
