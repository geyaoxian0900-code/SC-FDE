function receiver = fblms(channel, source, cfg)
%FBLMS Frequency-domain block LMS equalizer module (book Fig. 4-25).
%   RECEIVER = FBLMS(CHANNEL, SOURCE, CFG) runs the strict overlap-save
%   frequency-domain block adaptive equalizer on the received symbols
%   and returns symbol estimates aligned with source.tx.
%
%   cfg.fblmsBlockLength  - block length N (default 64)
%   cfg.fblmsFilterLength - filter length Nf (default 16)
%   cfg.fblmsStep         - NLMS step (default 0.3)
%   cfg.fblmsEpsilon      - regularization (default 1e-6)
%   cfg.trainingSymbols   - training length
%   cfg.fblmsDecisionDirected - use decision-directed error after the
%                               training segment (default true)
received = channel.received(:).';
reference = source.tx(:).';
cfg = scfde.equalizers.ch4_setup(cfg, numel(received));
trainLength = field_default(cfg, "trainingSymbols", ...
    min(round(numel(reference) / 2), numel(reference)));
% Default block size gives at least two training blocks so the
% scalar-denominator NLMS can converge inside the training segment.
blockLength = field_default(cfg, "fblmsBlockLength", ...
    min(64, max(8, floor(trainLength / 2))));
filterLength = field_default(cfg, "fblmsFilterLength", ...
    min(16, max(4, floor(blockLength / 4))));
step = field_default(cfg, "fblmsStep", 0.5);
epsilon = field_default(cfg, "fblmsEpsilon", 1e-6);
useDecisionFeedback = field_default(cfg, "fblmsDecisionDirected", true);
if isfield(cfg, "fblmsDecisionFcn")
    decisionFcn = cfg.fblmsDecisionFcn;
elseif isfield(cfg, "modulation") && strcmpi(cfg.modulation, "qpsk")
    decisionFcn = @qpsk_slice;
else
    decisionFcn = @bpsk_slice;
end
[output, ~, trace] = scfde.equalizers.fblms_equalizer(received, ...
    reference, trainLength, filterLength, blockLength, step, epsilon, ...
    useDecisionFeedback, decisionFcn);
% Turbo scenario: decode the equalized data segment through the (7,5)
% BCJR and return exactly 512 information-symbol decisions.  The QPSK
% scenario keeps the frame-symbol output.
if isfield(cfg, "permutation") && ~isempty(cfg.permutation)
    frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
    dataEqualized = output(frame.dataIndices);
    amplitude = mean(abs(real(dataEqualized)));
    llrFrame = zeros(1, frame.frameLength);
    llrFrame(frame.dataIndices) = 2 * real(dataEqualized) / ...
        max(amplitude, 1e-12) / max(cfg.noiseVariance, 1e-6);
    previous = zeros(1, frame.frameLength);
    previous(frame.trainingIndices) = frame.trainingSymbols;
    [bits, ~] = scfde.equalizers.ch4_decoder_feedback_frame( ...
        llrFrame, frame, previous, 1, cfg.turboDecoderMode);
    decisions = 1 - 2 * bits;
    trace.equalizedFrame = output;
    trace.softEstimates = output;
    trace.outputDomain = "information-symbols";
else
    % Align the output length with the reference.
    n = min(numel(output), numel(reference));
    decisions = output(1:n);
    trace.outputDomain = "frame-symbols";
end
receiver = scfde.equalizers.pack_equalizer("FBLMS", "fblms", ...
    decisions, zeros(size(decisions)), decisions, trace);
end

function value = field_default(cfg, name, defaultValue)
if isfield(cfg, name)
    value = cfg.(name);
else
    value = defaultValue;
end
end

function symbols = qpsk_slice(values)
% 4-quadrant unit-energy QPSK hard decision.
symbols = ((1 - 2 * (real(values) < 0)) + ...
    1j * (1 - 2 * (imag(values) < 0))) / sqrt(2);
end

function symbols = bpsk_slice(values)
symbols = sign(real(values));
symbols(symbols == 0) = 1;
end
