function w = ch2_wiener(Ru, Rdu)
%CH2_WIENER  Book eq.(2-11): Wiener (MMSE) equalizer coefficients.
%   w^o = R_u^{-1} R_du,  R_u = E[u u^H],  R_du = E[d u^*].
w = Ru \ Rdu;
end
