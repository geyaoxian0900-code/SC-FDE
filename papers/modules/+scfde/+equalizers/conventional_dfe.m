function receiver = conventional_dfe(channel, source, cfg)
%CONVENTIONAL_DFE Known-channel MMSE-DFE equalizer module (book 2-26)-(2-31).
[decisions, mse, estimates, trace] = scfde.equalizers.known_dfe_core( ...
    channel.received, source.tx, channel.impulse, cfg);
receiver = scfde.equalizers.pack_equalizer("Conventional DFE", "dfe", ...
    decisions, mse, estimates, trace);
end
