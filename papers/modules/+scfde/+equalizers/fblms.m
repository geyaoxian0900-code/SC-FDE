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
blockLength = field_default(cfg, "fblmsBlockLength", 64);
filterLength = field_default(cfg, "fblmsFilterLength", 16);
step = field_default(cfg, "fblmsStep", 0.3);
epsilon = field_default(cfg, "fblmsEpsilon", 1e-6);
trainLength = field_default(cfg, "trainingSymbols", ...
    min(round(numel(reference) / 2), numel(reference)));
useDecisionFeedback = field_default(cfg, "fblmsDecisionDirected", true);
[output, ~, trace] = scfde.equalizers.fblms_equalizer(received, ...
    reference, trainLength, filterLength, blockLength, step, epsilon, ...
    useDecisionFeedback);
% Align the output length with the reference.
n = min(numel(output), numel(reference));
decisions = output(1:n);
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
