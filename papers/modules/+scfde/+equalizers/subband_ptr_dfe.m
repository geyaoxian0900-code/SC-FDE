function receiver = subband_ptr_dfe(channel, source, cfg)
%SUBBAND_PTR_DFE Subarray passive time-reversal front end + known DFE
% (book (2-48)/(2-49)):
%   y_p(n) = sum_{k in subarray p} h_k*(-n) * r_k(n),   p = 1..P,
%   d_hat(n) = sum_p a_p^H y_p(n) - b^H d~(n),
% with the per-subarray equivalent channels
%   g_p = sum_{k in subarray p} h_k*(-n) * h_k   (per-element
%   autocorrelation sums; NO |sum_k h_k|^2 cross-element terms).
%   The M elements are split into P = min(numSubbands, M) subarrays
%   (round-robin grouping); the post-stage is the P-branch known Wiener
%   DFE (2-49).  Single-branch fallback (P = 1) when the channel has no
%   multi-element branch data (the scenario default).
branches = [];
branchImpulses = [];
if isfield(channel, "branches")
    branches = channel.branches;
end
if isfield(channel, "branchImpulses")
    branchImpulses = channel.branchImpulses;
end
branchCount = max(1, size(branches, 1));
subarrays = max(1, min(cfg.numSubbands, branchCount));
if branchCount < 2 || isempty(branchImpulses) || ...
        size(branchImpulses, 1) < 2
    % Single-branch fallback: the front end reduces to the (2-47) form.
    subband = scfde.equalizers.subband_ptr(channel.received, channel.impulse, ...
        cfg.numSubbands, cfg.ptrRegularization, branches, branchImpulses);
    % The front end falls back to a single branch when branches is
    % missing; the equivalent channel must use the same effective
    % branch count.
    equivalent = scfde.equalizers.subband_equivalent_channel( ...
        channel.impulse, branchImpulses, branchCount);
    [decisions, mse, ~, trace] = scfde.equalizers.known_dfe_core( ...
        subband, source.tx, equivalent, cfg);
    estimate = subband;
else
    % P-subarray structure (2-48): round-robin element grouping.
    yMatrix = complex(zeros(subarrays, size(branches, 2)));
    equivalents = cell(1, subarrays);
    for p = 1:subarrays
        group = p:subarrays:branchCount;
        groupBranches = branches(group, :);
        groupImpulses = branchImpulses(group, :);
        yMatrix(p, :) = scfde.equalizers.subband_ptr( ...
            branches(1, :), channel.impulse, cfg.numSubbands, ...
            cfg.ptrRegularization, groupBranches, groupImpulses);
        equivalents{p} = scfde.equalizers.subband_equivalent_channel( ...
            channel.impulse, groupImpulses, numel(group));
    end
    [decisions, mse, ~, trace] = scfde.equalizers.multibranch_known_dfe_core( ...
        yMatrix, source.tx, cfg, equivalents);
    % The focused (matched-filtered) stream is the soft PTR output.
    estimate = sum(yMatrix, 1);
end
% The subband PTR front-end output is the soft output of the passive
% time-reversal (matched-filter) processing (see ptr_dfe).
trace.subarrayCount = subarrays;
trace.subbandStructure = "(2-48)/(2-49) P subarrays y_p = sum_k h_k*(-n)*r_k; g_p = sum_k h_k*(-n)*h_k (no cross terms)";
trace.formulaStatus = "BOOK-EXACT";
receiver = scfde.equalizers.pack_equalizer("Subband passive TR-DFE", ...
    "subband-ptr-dfe", decisions, mse, estimate, trace);
end
