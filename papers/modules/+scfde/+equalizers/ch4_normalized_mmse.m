function weights = ch4_normalized_mmse(H, noiseVariance)
weights = conj(H) ./ (abs(H).^2 + noiseVariance);
weights = weights / max(real(mean(weights .* H)), eps);
end
