function [informationLlr, codedLlr, metric] = ch4_bcjr_siso_decode(codedLlr, mode)
mode = scfde.equalizers.ch4_canonical_decoder_mode(mode);
if mode == "MAP"
    [informationLlr, codedLlr, metric] = scfde.equalizers.ch4_bcjr_probability(codedLlr);
else
    [informationLlr, codedLlr, metric] = scfde.equalizers.ch4_bcjr_log_domain(codedLlr, mode);
end
end