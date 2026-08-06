function reliability = ch3_symbol_reliability(symbols, noiseVariance)
posterior = scfde.equalizers.ch3_qpsk_posterior_mean(symbols, noiseVariance);
reliability = min(0.999, mean(abs(posterior).^2));
end
