function receiver = fdda_dfe_teq(channel, source, cfg)
%FDDA_DFE_TEQ Frequency-domain direct adaptive DFE turbo equalizer: a
% project combination that reuses the SAME shared FDDA kernel as
% fdda-teq (ch4_fdda_teq_core, book (4-74)~(4-82)); only the feedback
% source differs.  The registered name is not an independent book method,
% so its maximum certification is ALG-EQUIV (never BOOK-EXACT).
%
%   Feedback source (cfg.fddaDfeFeedbackMode):
%     "hard"       (default) sign(real(previous equalized data symbols))
%     "turbo-soft" decoder-derived soft symbols E[x | LLR] (explicit
%                  engineering extension)
%   Inner round 1 has zero data feedback (the kernel's (4-75) rule); the
%   final inner-round output is de-interleaved and soft-decoded by the
%   (7,5) BCJR into exactly 512 information decisions.
%
%   FDDA parameters are passed through to the shared kernel: fddaStepFf,
%   fddaStepFb, fddaBlockLength, fddaFfLength, fddaFbLength,
%   fddaForgetting/FddaForgettingF/FddaForgettingB, fddaDenomMode,
%   fddaRegularization.  The BLMS parameters (blmsStep, blmsLeakage,
%   blmsRegularization) are no longer read at all.
%
%   hopLength: the overlapping-window output stitching rule is still
%   SOURCE-UNCERTAIN, so this decoder-driving wrapper runs CONTIGUOUS
%   windows (hopLength = blockLength); cfg.fddaHopLength is reserved but
%   not honored until the stitching rule is source-confirmed (recorded
%   in trace.hopMode).
%
%   The scenario owns the interleaver; the module never resets the
%   global RNG.  trace.kernel = "fdda" identifies the shared kernel.
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);  % validates
received = channel.received(:).';
training = source.training(:).';
trainLength = field_default(cfg, "trainingSymbols", numel(training));
iterations = field_default(cfg, "fddaInnerIterations", ...
    field_default(cfg, "iterations", 3));
blockLength = field_default(cfg, "fddaBlockLength", 32);
params = struct("blockLength", blockLength, ...
    "ffLength", field_default(cfg, "fddaFfLength", 32), ...
    "fbLength", field_default(cfg, "fddaFbLength", 10), ...
    "hopLength", blockLength, ...                 % contiguous (see header)
    "ffConstraintLength", field_default(cfg, "fddaFfLength", 32), ...
    "fbConstraintLength", field_default(cfg, "fddaFbLength", 10), ...
    "stepFf", field_default(cfg, "fddaStepFf", 0.2), ...
    "stepFb", field_default(cfg, "fddaStepFb", 0.01), ...
    "innerIterations", iterations, ...
    "outerIterations", iterations, ...
    "forgettingF", field_default(cfg, "fddaForgettingF", ...
        field_default(cfg, "fddaForgetting", 0.97)), ...
    "forgettingB", field_default(cfg, "fddaForgettingB", ...
        field_default(cfg, "fddaForgetting", 0.97)), ...
    "denomMode", field_default(cfg, "fddaDenomMode", "equation"), ...
    "regularization", field_default(cfg, "fddaRegularization", 1e-6), ...
    "trainLength", trainLength);
params.decisionFn = @(x) sign(real(x));
nData = numel(received) - trainLength;
if nData > 0
    params.referenceData = source.tx(trainLength + 1:min( ...
        trainLength + nData, numel(source.tx)));
end
feedbackMode = lower(string(field_default(cfg, "fddaDfeFeedbackMode", "hard")));
feedbackFn = @(innerRound, dataOut) make_dfe_feedback(innerRound, ...
    dataOut, feedbackMode, cfg, trainLength);
[dataOut, trace] = scfde.equalizers.ch4_fdda_teq_core( ...
    received, training, params, feedbackFn);
trace.kernel = "fdda";
% Certification override: fdda-dfe-teq is a project combination that
% reuses the shared FDDA kernel; it is NOT an independent book method,
% so the kernel's BOOK-EXACT status never applies to this registered
% method (maximum certification is ALG-EQUIV).
trace.formulaStatus = "ALG-EQUIV";
trace.formulaMode = "project-combination";
trace.bookExperimentEquivalent = false;
trace.feedbackMode = char(feedbackMode);
trace.hopMode = "contiguous (overlap stitching SOURCE-UNCERTAIN)";
trace.iterationError = trace.iterationMse;
trace.iterationBer = trace.decisionBer;
% Final decision: de-interleave the last data-segment symbols and run the
% (7,5) BCJR decoder (same path as fdda-teq).
if isfield(cfg, "permutation") && ~isempty(cfg.permutation) && ...
        ~isempty(dataOut)
    permutation = cfg.permutation;
    inversePermutation = zeros(1, numel(permutation));
    inversePermutation(permutation) = 1:numel(permutation);
    amplitude = mean(abs(real(dataOut(1:numel(permutation)))));
    codedLlr = real(dataOut(1:numel(permutation))) / ...
        max(amplitude, 1e-12) * 2 / ...
        max(field_default(cfg, "noiseVariance", 1e-3), 1e-6);
    [informationLlr, ~] = scfde.equalizers.ch4_bcjr_siso_decode( ...
        codedLlr(inversePermutation), ...
        field_default(cfg, "turboDecoderMode", "Log-MAP"));
    bits = informationLlr < 0;
    decisions = 1 - 2 * bits;
else
    decisions = dataOut;
end
receiver = scfde.equalizers.pack_equalizer("FDDA-DFE-TEQ", ...
    "fdda-dfe-teq", decisions, zeros(size(decisions)), decisions, trace);
end

function softData = make_dfe_feedback(innerRound, dataOut, mode, cfg, ...
    trainLength) %#ok<INUSD>
% Feedback/error reference for the NEXT inner round (frame-aligned):
%   "hard"       - hard decisions of the previous inner round's data
%                  segment (DFE mode, default)
%   "turbo-soft" - decoder soft symbols E[x | LLR] (engineering extension)
if strcmpi(mode, "turbo-soft") && isfield(cfg, "permutation") && ...
        ~isempty(cfg.permutation)
    permutation = cfg.permutation;
    inversePermutation = zeros(1, numel(permutation));
    inversePermutation(permutation) = 1:numel(permutation);
    codedLlr = real(dataOut(1:numel(permutation))) * 2 / ...
        max(field_default(cfg, "noiseVariance", 1e-3), 1e-6);
    equalizerInput = codedLlr(inversePermutation);
    [~, codedDecoded] = scfde.equalizers.ch4_bcjr_siso_decode( ...
        equalizerInput, ...
        field_default(cfg, "turboDecoderMode", "Log-MAP"));
    extrinsic = codedDecoded - equalizerInput;
    softData = tanh(extrinsic(permutation) / 2);
else
    softData = sign(real(dataOut));
end
softData = softData(:).';
end

function value = field_default(cfg, name, defaultValue)
if isfield(cfg, name) && ~isempty(cfg.(name))
    value = cfg.(name);
else
    value = defaultValue;
end
end
