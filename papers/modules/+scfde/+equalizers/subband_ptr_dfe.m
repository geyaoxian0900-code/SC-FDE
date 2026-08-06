function receiver = subband_ptr_dfe(channel, source, cfg)
%SUBBAND_PTR_DFE Subarray passive time-reversal front end + known DFE
% (book 2-48)-(2-49): each branch is time-reversal matched filtered with
% its own channel h_k*(-n) and combined, then a known-channel DFE runs on
% the focused signal.
timeReversal = conj(fliplr(channel.impulse));
branches = [];
branchImpulses = [];
if isfield(channel, "branches")
    branches = channel.branches;
end
if isfield(channel, "branchImpulses")
    branchImpulses = channel.branchImpulses;
end
subband = scfde.equalizers.subband_ptr(channel.received, channel.impulse, ...
    cfg.numSubbands, cfg.ptrRegularization, branches, branchImpulses);
[decisions, mse, estimates, trace] = scfde.equalizers.known_dfe_core( ...
    subband, source.tx, conv(timeReversal, channel.impulse), cfg);
receiver = scfde.equalizers.pack_equalizer("Subband passive TR-DFE", "subband-ptr-dfe", ...
    decisions, mse, estimates, trace);
end
