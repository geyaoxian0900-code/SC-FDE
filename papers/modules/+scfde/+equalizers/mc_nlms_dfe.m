function receiver = mc_nlms_dfe(channel, source, cfg)
%MC_NLMS_DFE Multichannel NLMS DFE equalizer module ((2-44)~(2-46) + (2-16)).
[decisions, mse, estimates, trace] = scfde.equalizers.multichannel_dfe_core( ...
    channel.branches, source.tx, cfg, "nlms");
% Composite input u = [r_1 e^{-j theta_1}; ...; r_P e^{-j theta_P}; -d~]
% with ONE normalized update (2-16); per-element independent DPLL loops.
trace.updateEquation = "(2-44)~(2-46) composite u with per-element rotations + (2-16) single NLMS update";
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = trace.parameters;
receiver = scfde.equalizers.pack_equalizer("Multichannel NLMS DFE", "mc-nlms-dfe", ...
    decisions, mse, estimates, trace);
end
