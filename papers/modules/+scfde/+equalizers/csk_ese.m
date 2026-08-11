function receiver = csk_ese(channel, source, cfg)
%CSK_ESE CSK-IDMA ESE iterative receiver (book 6.3, 6-21~6-36).
% ESE outputs information-symbol decisions (repetition-1/2 outer code);
% the exported symbol estimates fall back to a matched-filter hard
% decision so the unified BER comparison stays on codeword indices.
codeLength = numel(channel.impulse);
if isfield(cfg, "codeLength"), codeLength = cfg.codeLength; end
M = 4;
if isfield(cfg, "cskOrder"), M = cfg.cskOrder; end
users = 1;
if isfield(cfg, "idmaUsers"), users = cfg.idmaUsers; end
symbols = min(floor(numel(channel.received) / codeLength), ...
    floor(numel(source.data) / codeLength));
innerIterations = 3;
outerIterations = 3;
if isfield(cfg, "innerIterations"), innerIterations = cfg.innerIterations; end
if isfield(cfg, "outerIterations"), outerIterations = cfg.outerIterations; end
root = scfde.equalizers.ch6_select_csk_root(codeLength);
[book, bits] = scfde.equalizers.ch6_csk_codebook(root, M);
channels = scfde.equalizers.ch6_dictionary_channels( ...
    channel.impulse, users, codeLength);
[dicts, userChannels] = scfde.equalizers.ch6_idma_dictionaries(book, channels, users);
conventional = scfde.equalizers.ch6_conventional_dictionaries(book, channels, users);
pair = scfde.equalizers.ch6_repeated_symbol_indices(M, symbols, users);
received = reshape(channel.received(1:symbols * codeLength), codeLength, symbols).';
noiseVariance = cfg.noiseVariance * ones(1, users);
transmitted = zeros(users, symbols, codeLength);
[innerDecision, outerDecision, ~, ~, ~, ~] = scfde.equalizers.ch6_csk_idma_detect( ...
    received, dicts, userChannels, noiseVariance, pair, ...
    innerIterations, outerIterations, transmitted, false, 0.9);
% Fallback hard decisions on codeword indices (matched filter against the
% conventional dictionary, matching the unified link's transmitted frame)
mfIndices = zeros(1, symbols);
for symbol = 1:symbols
    [mfIndices(symbol), ~] = scfde.equalizers.ch6_hard_dictionary_detect( ...
        received(symbol, :), conventional{1});
end
decisions = zeros(1, symbols * codeLength);
for symbol = 1:symbols
    decisions((symbol - 1) * codeLength + (1:codeLength)) = ...
        book(mfIndices(symbol), :);
end
infoIndices = squeeze(outerDecision(end, :, 1)).';
% Soft chip output: circular matched filter of the received chips
% with the channel (consistent with csk_matched_filter), so the
% constellation shows the soft spreading-chip estimates.
softChips = ifft(conj(fft(channel.impulse, numel(channel.received))) .* ...
    fft(channel.received));
receiver = scfde.equalizers.pack_equalizer("CSK-IDMA-ESE", "csk-ese", ...
    decisions, zeros(size(decisions)), softChips, ...
    struct("indices", mfIndices, "infoIndices", infoIndices));
end
