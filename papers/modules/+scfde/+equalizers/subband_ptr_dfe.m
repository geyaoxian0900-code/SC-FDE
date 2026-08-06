function receiver = subband_ptr_dfe(channel, source, cfg)
%SUBBAND_PTR_DFE Subband passive time-reversal front end + known DFE (2-48)-(2-49).
timeReversal = conj(fliplr(channel.impulse));
subband = scfde.equalizers.subband_ptr(channel.received, channel.impulse, ...
    cfg.numSubbands, cfg.ptrRegularization);
[decisions, mse, estimates, trace] = scfde.equalizers.known_dfe_core( ...
    subband, source.tx, conv(timeReversal, channel.impulse), cfg);
receiver = scfde.equalizers.pack_equalizer("Subband passive TR-DFE", "subband-ptr-dfe", ...
    decisions, mse, estimates, trace);
end
