function receiver = dpll_dfe(channel, source, cfg)
%DPLL_DFE NLMS DFE with DPLL carrier-phase tracking (book 2-35)-(2-43).
[decisions, mse, estimates, trace] = scfde.equalizers.adaptive_dfe_core( ...
    channel.received, source.tx, cfg, "nlms", true);
receiver = scfde.equalizers.pack_equalizer("DPLL-DFE", "dpll-dfe", ...
    decisions, mse, estimates, trace);
end
