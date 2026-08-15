function receiver = htfde(channel, source, cfg)
%HTFDE Hybrid time-frequency domain decision-feedback equalizer module
% (book (3-61)/(3-62) + multichannel DPLL-DFE (2-26)~(2-43),(2-43)~(2-46)).
%
%   Book path: each element's received signal is jointly MMSE-equalized
%   in the frequency domain inside its sub-array,
%       x_m = IFFT{ sum_k C_{m,k} R_{m,k} },
%   and the P sub-array outputs feed a multichannel time-domain DFE with
%   one second-order DPLL per sub-array.  The front-end lambda comes only
%   from the residual phase matrix (3-39)~(3-41) (default lambda = 1,
%   the strict D = I degradation); the DPLL never feeds the front end.
%
%   Modes (explicit cfg.htfdeMode):
%     "book"        requires explicit cfg.htfdeSubarrayCount (P) and
%                   cfg.htfdeElementsPerSubarray (K); M = P*K must equal
%                   the branch count.  Missing P/K raises
%                   SCFDE:BookParameterUnavailable (book values are
%                   PARAM-UNRECOVERABLE).
%     "engineering" explicit degenerate smoke structure P=1, K=1;
%                   metadata marks scenarioMode="engineering".
%   bookExperimentEquivalent is always false until the book's experiment
%   configuration is confirmed by human scan review.
%
%   The legacy segmented branch-phase implementation is retained in
%   ch3_htfde_equalize_engineering.m (htfde_engineering module).
N = numel(channel.received);
cfg = scfde.equalizers.ch3_setup(cfg, N, numel(source.data));
mode = lower(string(htfde_field_default(cfg, "htfdeMode", "book")));
trace = struct();
if mode == "book"
    if ~isfield(cfg, "htfdeSubarrayCount") || ...
            ~isfield(cfg, "htfdeElementsPerSubarray")
        error("SCFDE:BookParameterUnavailable", ...
            "htfde BOOK mode requires explicit htfdeSubarrayCount (P) " + ...
            "and htfdeElementsPerSubarray (K): the book experiment " + ...
            "values are not published (PARAM-UNRECOVERABLE).");
    end
    trace.scenarioMode = "book-structure";
else
    cfg.htfdeSubarrayCount = htfde_field_default(cfg, "htfdeSubarrayCount", 1);
    cfg.htfdeElementsPerSubarray = ...
        htfde_field_default(cfg, "htfdeElementsPerSubarray", 1);
    trace.scenarioMode = "engineering";
end
trace.bookExperimentEquivalent = false;
trace.formulaStatus = "BLOCKED-SOURCE-REVIEW";
trace.formulaMode = string(mode);
trace.formulaNote = "(3-61)/(3-62): implemented per the scan-confirmed per-element matrix form x_m = IFFT{ sum_k C_{m,k} R_{m,k} } with the sub-array sum; the lambda-subscript transcription of (3-61) remains SOURCE-INCONSISTENT (implemented with the default lambda = 1 degradation D = I and the residual-phase-matrix lambda from (3-39)~(3-41)) -> weakest-link certification BLOCKED-SOURCE-REVIEW pending human re-review of the scan; experiment parameters (P/K/DPLL gains) PARAM-UNRECOVERABLE";
trace.effectiveParameters = struct( ...
    "subarrayCount", cfg.htfdeSubarrayCount, ...
    "elementsPerSubarray", cfg.htfdeElementsPerSubarray, ...
    "feedforwardTaps", htfde_field_default(cfg, "feedforwardTaps", 12), ...
    "feedbackTaps", htfde_field_default(cfg, "feedbackTaps", 6));
if isfield(channel, "branches")
    branches = channel.branches;
else
    branches = channel.received;
end
if isfield(channel, "branchImpulses")
    branchImpulses = channel.branchImpulses;
else
    branchImpulses = channel.impulse;
end
if isvector(branches)
    branches = branches(:).';
end
if isvector(branchImpulses)
    branchImpulses = branchImpulses(:).';
end
[subarrayOutputs, frontEndTrace] = scfde.equalizers.ch3_htfde_equalize( ...
    branches, branchImpulses, cfg.noiseVariance, cfg);
[decisions, mse, estimates, dpllTrace] = ...
    scfde.equalizers.multichannel_dpll_dfe_core( ...
    subarrayOutputs, source.tx, cfg);
trace.subarrayOutputs = subarrayOutputs;
trace.frontEnd = frontEndTrace;
trace.dpll = dpllTrace;
% Full-block output: the qpsk metric adapter recognizes numel(out)==N and
% slices payload = trainingSymbols+1:dataSymbols, so the known training
% symbols never enter the BER statistics (per-frame totalBits = 112).
receiver = scfde.equalizers.pack_equalizer("HTFDE", "htfde", ...
    decisions, mse, estimates, trace);
end

function v = htfde_field_default(s, name, defaultValue)
if isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = defaultValue;
end
end
