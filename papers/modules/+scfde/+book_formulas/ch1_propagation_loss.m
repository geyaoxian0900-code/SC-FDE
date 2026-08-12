function tl = ch1_propagation_loss(l, f, k)
%CH1_PROPAGATION_LOSS  Book eq.(1-2)/(1-3): propagation loss.
%   A(l,f) = l^k [a(f)]^l,  TL = 10 lg A = k*10 lg(1000/l) + l*10 lg a(f)
%   l [km], f [kHz], k spreading factor (2 spherical / 1 cylindrical).
%   Returns TL in dB.
aDb = scfde.book_formulas.ch1_thorp_absorption(f);
tl = k * 10 * log10(1000 ./ l) + l .* aDb;
end
