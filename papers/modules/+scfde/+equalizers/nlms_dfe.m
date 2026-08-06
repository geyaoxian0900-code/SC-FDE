function receiver = nlms_dfe(channel, source, cfg)
%NLMS_DFE NLMS adaptive DFE equalizer module (book 2-16).
[decisions, mse, estimates, trace] = scfde.equalizers.adaptive_dfe_core( ...
    channel.received, source.tx, cfg, "nlms", false);
receiver = scfde.equalizers.pack_equalizer("NLMS adaptive DFE", "nlms-dfe", ...
    decisions, mse, estimates, trace);
end
