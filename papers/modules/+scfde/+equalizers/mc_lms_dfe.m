function receiver = mc_lms_dfe(channel, source, cfg)
%MC_LMS_DFE Multichannel LMS DFE equalizer module ((2-43)~(2-46) + (2-14)).
[decisions, mse, estimates, trace] = scfde.equalizers.multichannel_dfe_core( ...
    channel.branches, source.tx, cfg, "lms");
% Per-element independent DPLL loops, coherent feedforward sum, shared
% feedback; composite LMS update (mu_a = mu_b = lmsStep/2).
trace.updateEquation = "(2-43)~(2-46) per-element DPLL + (2-14) composite LMS (mu_a=mu_b=lmsStep/2)";
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = trace.parameters;
receiver = scfde.equalizers.pack_equalizer("Multichannel LMS DFE", "mc-lms-dfe", ...
    decisions, mse, estimates, trace);
end
