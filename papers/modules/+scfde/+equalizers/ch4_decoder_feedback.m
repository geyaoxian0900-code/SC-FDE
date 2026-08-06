function [bits, decoderLlr, softSymbols] = ch4_decoder_feedback(equalizerLlr, ...
        permutation, inversePermutation, previousSoftSymbols, cfg)
equalizerInput = equalizerLlr(inversePermutation);
[informationLlr, codedLlr] = scfde.equalizers.ch4_bcjr_siso_decode( ...
    equalizerInput, "Log-MAP");
decoderExtrinsic = codedLlr - equalizerInput;
decoderLlr = decoderExtrinsic(permutation);
decoderPosterior = codedLlr(permutation);
candidate = tanh(decoderPosterior / 2);
softSymbols = (1 - cfg.turboDamping) * previousSoftSymbols + ...
    cfg.turboDamping * candidate;
bits = informationLlr < 0;
end