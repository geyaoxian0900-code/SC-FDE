function word = ch5_cck_word(phase)
phi1 = phase(1); phi2 = phase(2); phi3 = phase(3); phi4 = phase(4);
word = exp(1j * [phi1 + phi2 + phi3 + phi4, phi1 + phi3 + phi4, ...
    phi1 + phi2 + phi4, phi1 + phi4, phi1 + phi2 + phi3, phi1 + phi3, ...
    phi1 + phi2, phi1]);
word([4, 7]) = -word([4, 7]);
end
