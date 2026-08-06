function receiver = mc_rls_dfe(channel, source, cfg)
%MC_RLS_DFE Multichannel RLS DFE equalizer module.
[decisions, mse, estimates, trace] = scfde.equalizers.multichannel_dfe_core( ...
    channel.branches, source.tx, cfg, "rls");
receiver = scfde.equalizers.pack_equalizer("Multichannel RLS DFE", "mc-rls-dfe", ...
    decisions, mse, estimates, trace);
end
