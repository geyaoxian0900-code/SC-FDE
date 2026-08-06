function receiver = mc_lms_dfe(channel, source, cfg)
%MC_LMS_DFE Multichannel LMS DFE equalizer module.
[decisions, mse, estimates, trace] = scfde.equalizers.multichannel_dfe_core( ...
    channel.branches, source.tx, cfg, "lms");
receiver = scfde.equalizers.pack_equalizer("Multichannel LMS DFE", "mc-lms-dfe", ...
    decisions, mse, estimates, trace);
end
