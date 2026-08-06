function softSymbols = ch4_initial_soft_feedback(Y, Hinitial, noiseVariance, ...
        permutation, inversePermutation)
initialEstimate = ifft(scfde.equalizers.ch4_normalized_mmse(Hinitial, noiseVariance) .* Y);
initialLlr = 2 * real(initialEstimate) / noiseVariance;
equalizerInput = initialLlr(inversePermutation);
[~, codedLlr] = scfde.equalizers.ch4_bcjr_siso_decode(equalizerInput, "Log-MAP");
softSymbols = tanh(codedLlr(permutation) / 2);
end
