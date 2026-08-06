function X = ch3_mmse_frequency_equalize(Y, H, noiseVariance)
X = Y .* conj(H) ./ (abs(H).^2 + noiseVariance);
end
