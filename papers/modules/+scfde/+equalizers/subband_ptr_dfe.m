function receiver = subband_ptr_dfe(channel, source, cfg)
%SUBBAND_PTR_DFE Subarray passive time-reversal front end + known DFE
% (book 2-48)-(2-49): each branch is time-reversal matched filtered with
% its own channel h_k*(-n) and combined, then a known-channel DFE runs on
% the focused signal.  The DFE's equivalent channel is the per-branch
% autocorrelation sum g_p = sum_k h_k*(-n) * h_k (no cross-branch terms).
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
% The front end falls back to a single branch when branches is missing;
% the equivalent channel must use the same effective branch count.
branchCount = max(1, size(branches, 1));
equivalent = scfde.equalizers.subband_equivalent_channel( ...
    channel.impulse, branchImpulses, branchCount);
[decisions, mse, ~, trace] = scfde.equalizers.known_dfe_core( ...
    subband, source.tx, equivalent, cfg);
% The subband PTR front-end output is the soft output of the passive
% time-reversal (matched-filter) processing (see ptr_dfe).
receiver = scfde.equalizers.pack_equalizer("Subband passive TR-DFE", "subband-ptr-dfe", ...
    decisions, mse, subband, trace);
end
