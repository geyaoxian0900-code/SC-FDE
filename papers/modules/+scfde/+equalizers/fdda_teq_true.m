function receiver = fdda_teq_true(channel, source, cfg)
%FDDA_TEQ_TRUE Frequency-domain direct adaptive turbo equalizer
% (book Fig. 4-25, Eqs. 4-81/4-82) on the shared kernel
% ch4_fdda_teq_core.
%   RECEIVER = FDDA_TEQ_TRUE(CHANNEL, SOURCE, CFG)
%
% The book simulation parameters are mu_f=0.2, mu_b=0.01, N_c=32,
% N_f=32, N_b=10, I_inner=1, I_outer=3.  The kernel updates W and B on
% EVERY block (training mode and decision-directed mode, Eq. 4-82)
% with the exponential forgetting factor gamma^block, and inherits the
% filters across outer iterations (Eq. 4-81).  The data segment of the
% first outer iteration uses hard-decision errors; later outer
% iterations use the BCJR soft symbols (coded frame) as the error and
% feedback references.
%
% The frame must be [training; data] (see run_turbo_scenario).  The
% interleaver is supplied by the scenario (cfg.permutation); the module
% never resets the global RNG.  W starts at the unit impulse and B at
% zero (no true-channel initialization).
%
% cfg.iterations or cfg.fddaIterations - I_outer (default 3, the book
%                                        value)
% cfg.fddaStepFf/fddaStepFb - mu_f/mu_b (defaults 0.2/0.01)
% cfg.fddaBlockLength/fddaFfLength/fddaFbLength - Nc/Nf/Nb (32/32/10)
% cfg.fddaForgetting - gamma, the exponential forgetting factor
%                      (default 0.97; engineering parameter, the book
%                      gives gamma < 1 without a value)
% cfg.fddaDenomMode - "bin" (per-bin, default) or "block" denominator
% cfg.trainingSymbols - training length
% cfg.permutation / cfg.noiseVariance / cfg.turboDecoderMode - BCJR

received = channel.received(:).';
training = source.training(:).';
if isfield(cfg, "trainingSymbols")
    trainLength = cfg.trainingSymbols;
else
    trainLength = numel(training);
end
if isfield(cfg, "iterations")
    outerIterations = cfg.iterations;
else
    outerIterations = field_default(cfg, "fddaIterations", 3);
end
params = struct("blockLength", field_default(cfg, "fddaBlockLength", 32), ...
    "ffLength", field_default(cfg, "fddaFfLength", 32), ...
    "fbLength", field_default(cfg, "fddaFbLength", 10), ...
    "stepFf", field_default(cfg, "fddaStepFf", 0.2), ...
    "stepFb", field_default(cfg, "fddaStepFb", 0.01), ...
    "outerIterations", outerIterations, ...
    "forgetting", field_default(cfg, "fddaForgetting", 0.97), ...
    "denomMode", field_default(cfg, "fddaDenomMode", "bin"), ...
    "trainLength", trainLength);
nData = numel(received) - trainLength;
if nData > 0
    params.referenceData = source.tx(trainLength + 1:min( ...
        trainLength + nData, numel(source.tx)));
end
decisionFn = @(x) sign(real(x));
params.decisionFn = decisionFn;
softFn = @(outer, dataOut) make_soft_feedback(outer, dataOut, cfg, ...
    trainLength, nData, source);
[dataOut, trace] = scfde.equalizers.ch4_fdda_teq_core( ...
    received, training, params, softFn);
% Iteration diagnostics from the kernel: true-data MSE and
% decision-directed BER per outer iteration (same reference: the
% transmitted data symbols).
trace.iterationError = trace.iterationMse;
trace.iterationBer = trace.decisionBer;
% Final decision: de-interleave the last data-segment symbols and run
% the (7,5) BCJR decoder (consistent with the other turbo equalizers).
if isfield(cfg, "permutation") && ~isempty(cfg.permutation)
    permutation = cfg.permutation;
    inversePermutation = zeros(1, numel(permutation));
    inversePermutation(permutation) = 1:numel(permutation);
    % Normalize the equalized amplitude before the LLR scaling: the
    % soft feedback changes the filter gain across outer iterations,
    % so real(dataOut) is scaled to unit mean magnitude.
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
receiver = scfde.equalizers.pack_equalizer("FDDA-TEQ", "fdda-teq", ...
    decisions, zeros(size(decisions)), decisions, trace);
end

function softData = make_soft_feedback(outer, dataOut, cfg, ...
    trainLength, nData, source)
% Feedback/error reference for the next outer iteration (Eq. 4-82
% Xtilde): the output feeds BOTH the feedback spectrum and the data
% error E(k) of the next outer iteration (see the kernel).
%   'decision' (default) - hard decisions, the book's decision-directed
%                          mode
%   'equalized'          - engineering extension: the raw equalized
%                          data segment (soft)
%   'bcjr'               - engineering extension: BCJR extrinsic-tanh
%                          soft symbols
% The BCJR soft decoding is always applied to the FINAL output
% ("the last inner iteration output is fed to the demodulator for soft
% decoding").
mode = field_default(cfg, "fddaSoftFeedback", "decision");
if strcmpi(mode, "equalized")
    softData = dataOut;
elseif strcmpi(mode, "bcjr") && isfield(cfg, "permutation") && ...
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
    % 'decision' (default): the book decision-directed mode.
    softData = sign(real(dataOut));
end
end

function value = field_default(cfg, name, defaultValue)
if isfield(cfg, name)
    value = cfg.(name);
else
    value = defaultValue;
end
end
