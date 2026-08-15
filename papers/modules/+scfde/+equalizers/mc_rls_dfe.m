function receiver = mc_rls_dfe(channel, source, cfg)
%MC_RLS_DFE Multichannel RLS DFE equalizer module ((2-44)~(2-46) + (2-23)~(2-25)).
[decisions, mse, estimates, trace] = scfde.equalizers.multichannel_dfe_core( ...
    channel.branches, source.tx, cfg, "rls");
% Composite input u = [r_1 e^{-j theta_1}; ...; r_P e^{-j theta_P}; -d~];
% P spans the full P*Nf+Nb dimension ((2-23)~(2-25)); per-element
% independent DPLL loops.
trace.updateEquation = "(2-44)~(2-46) composite u + (2-23)~(2-25) RLS, P dimension = P*Nf+Nb";
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = trace.parameters;
receiver = scfde.equalizers.pack_equalizer("Multichannel RLS DFE", "mc-rls-dfe", ...
    decisions, mse, estimates, trace);
end
