function receiver = lms_dfe(channel, source, cfg)
%LMS_DFE LMS adaptive DFE equalizer module (book 2-12)-(2-14).
[decisions, mse, estimates, trace] = scfde.equalizers.adaptive_dfe_core( ...
    channel.received, source.tx, cfg, "lms", false);
receiver = scfde.equalizers.pack_equalizer("LMS adaptive DFE", "lms-dfe", ...
    decisions, mse, estimates, trace);
end
