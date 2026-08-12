function ahat = ch6_csk_correlate(o, a, G)
%CH6_CSK_CORRELATE  Book eq.(6-7): cyclic-shift correlation detector.
%   ahat = (1/G) Re{ F^{-1}{ (F a)^* .* (F o) } }
%   o: received sequence, a: reference sequence, G: spreading gain.
F = dft_book(numel(o));
ahat = (1 / G) * real(ifft(conj(F * a(:)) .* (F * o(:))));
end

function F = dft_book(N)
n = (0:N - 1).';
k = 0:N - 1;
F = exp(-1j * 2 * pi * (k .* n) / N);
end
