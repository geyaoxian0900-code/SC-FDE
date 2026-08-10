function frame = ch4_turbo_frame_contract(channel, source, cfg)
%CH4_TURBO_FRAME_CONTRACT Validated Chapter-4 turbo frame descriptor.
%   FRAME = CH4_TURBO_FRAME_CONTRACT(CHANNEL, SOURCE, CFG)
%
% The Chapter-4 turbo frame is exactly
%       [256 known training symbols ; 1024 interleaved rate-1/2 (7,5)_8
%        convolutionally coded BPSK data symbols]
% i.e. 1280 received samples carrying 512 information bits.
%
% The descriptor exposes the training/data/information index ranges,
% the training symbols, the information symbols and bits, and the
% scenario-owned interleaver (cfg.permutation) with its inverse.  The
% scenario owns the interleaver: the equalizer modules must consume
% cfg.permutation and must not call rng or randperm.
%
% Errors (SCFDE:TurboFrame, SCFDE:TurboPermutation) are raised when
% the received frame length, the training length, the information
% symbol count or the permutation do not match the contract exactly.
% Dimension mismatches are never fixed by truncating arrays.

received = channel.received(:).';
training = source.training(:).';
trainingLength = field_required(cfg, "trainingSymbols");
informationLength = field_required(cfg, "infoBits");
expectedCodedLength = 2 * informationLength;
if trainingLength ~= numel(training) || ...
        numel(received) ~= trainingLength + expectedCodedLength
    error("SCFDE:TurboFrame", ...
        "Expected %d training + %d coded samples; received %d samples.", ...
        trainingLength, expectedCodedLength, numel(received));
end
permutation = field_required(cfg, "permutation");
permutation = permutation(:).';
if numel(permutation) ~= expectedCodedLength || ...
        ~isequal(sort(permutation), 1:expectedCodedLength)
    error("SCFDE:TurboPermutation", ...
        "cfg.permutation must be a permutation of 1:%d.", expectedCodedLength);
end
informationSymbols = source.data(:).';
if numel(informationSymbols) ~= informationLength
    error("SCFDE:TurboFrame", ...
        "source.data must contain exactly %d information symbols.", ...
        informationLength);
end
inversePermutation = zeros(1, expectedCodedLength);
inversePermutation(permutation) = 1:expectedCodedLength;
frame = struct( ...
    "frameLength", numel(received), ...
    "trainingLength", trainingLength, ...
    "codedLength", expectedCodedLength, ...
    "informationLength", informationLength, ...
    "trainingIndices", 1:trainingLength, ...
    "dataIndices", trainingLength + (1:expectedCodedLength), ...
    "trainingSymbols", training, ...
    "informationSymbols", informationSymbols, ...
    "informationBits", double(informationSymbols < 0), ...
    "permutation", permutation, ...
    "inversePermutation", inversePermutation);
end

function value = field_required(cfg, name)
if ~isfield(cfg, name) || isempty(cfg.(name))
    error("SCFDE:TurboFrame", "Missing required cfg.%s.", name);
end
value = cfg.(name);
end
