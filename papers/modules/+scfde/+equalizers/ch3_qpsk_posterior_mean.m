function meanSymbols = ch3_qpsk_posterior_mean(symbols, noiseVariance)
hardSymbols = scfde.equalizers.ch3_qpsk_map(scfde.equalizers.ch3_qpsk_demap(symbols));
decisionVariance = mean(abs(symbols - hardSymbols).^2);
effectiveVariance = max(noiseVariance, decisionVariance);
scale = sqrt(2) / max(effectiveVariance, 1e-8);
meanSymbols = (tanh(scale * real(symbols)) + ...
    1j * tanh(scale * imag(symbols))) / sqrt(2);
end
