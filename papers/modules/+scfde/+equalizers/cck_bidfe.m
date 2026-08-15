function receiver = cck_bidfe(channel, source, cfg)
%CCK_BIDFE CCK bidirectional DFE receiver, BiDFE-1 (book 5.3.2).
% Equivalent to bi1 = fuse_scores(forward, backward) in static_receiver_frame.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
limit = 128;
if isfield(cfg, "receiverCandidateLimit"), limit = cfg.receiverCandidateLimit; end
[forward, forwardScores] = scfde.equalizers.ch5_dfe_detect( ...
    channel.received, book, channel.impulse, cfg.noiseVariance, limit);
[~, backwardScores] = scfde.equalizers.ch5_backward_dfe_detect( ...
    channel.received, book, channel.impulse, cfg.noiseVariance, limit);
detected = scfde.equalizers.ch5_fuse_scores(forwardScores, backwardScores);
decisions = cck_indices_to_symbols(detected, source, book);
% Soft chip output: circular matched filter of the received chips
% with the channel (consistent with cck_rake), so the constellation
% shows the soft axial-QPSK chip estimates instead of the hard
% decisions.
softChips = ifft(conj(fft(channel.impulse, numel(channel.received))) .* ...
    fft(channel.received));
receiver = scfde.equalizers.pack_equalizer("CCK-BiDFE-1", "cck-bidfe", ...
    decisions, zeros(size(decisions)), softChips, ...
    struct("indices", detected, "forward", forward, ...
    "formulaStatus", "BLOCKED-SOURCE-REVIEW", ...
    "formulaMode", "engineering", ...
    "bookExperimentEquivalent", false, ...
    "effectiveParameters", struct("candidateLimit", limit), ...
    "formulaNote", "(5-48)~(5-56) BiDFE-1: the exact INITIALIZATION and forward/backward execution order must be established from book/31.png and book/32.png before any BOOK-EXACT claim; the current execution order is an explicit ENGINEERING choice"));
end

function decisions = cck_indices_to_symbols(detected, source, book)
blockCount = numel(detected);
dataLength = numel(source.data);
decisions = zeros(1, dataLength);
for block = 1:min(blockCount, floor(dataLength / 8))
    decisions((block - 1) * 8 + (1:8)) = book(detected(block), :);
end
end
