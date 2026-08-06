function receiver = mc_nlms_dfe(channel, source, cfg)
%MC_NLMS_DFE Multichannel NLMS DFE equalizer module.
[decisions, mse, estimates, trace] = scfde.equalizers.multichannel_dfe_core( ...
    channel.branches, source.tx, cfg, "nlms");
receiver = scfde.equalizers.pack_equalizer("Multichannel NLMS DFE", "mc-nlms-dfe", ...
    decisions, mse, estimates, trace);
end
