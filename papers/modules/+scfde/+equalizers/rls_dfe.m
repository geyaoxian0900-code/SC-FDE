function receiver = rls_dfe(channel, source, cfg)
%RLS_DFE RLS adaptive DFE equalizer module (book 2-17)-(2-25).
[decisions, mse, estimates, trace] = scfde.equalizers.adaptive_dfe_core( ...
    channel.received, source.tx, cfg, "rls", false);
receiver = scfde.equalizers.pack_equalizer("RLS adaptive DFE", "rls-dfe", ...
    decisions, mse, estimates, trace);
end
