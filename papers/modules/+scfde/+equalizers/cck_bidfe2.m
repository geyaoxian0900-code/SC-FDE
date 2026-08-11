function receiver = cck_bidfe2(channel, source, cfg)
%CCK_BIDFE2 CCK bidirectional DFE receiver, BiDFE-2 with refinement (5.3.2).
% Equivalent to bi2 = bidirectional_refine(..., bi1, ...) in
% static_receiver_frame: fuse forward/backward scores, then refine using
% candidate scores with the fused decisions as the channel state.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
limit = 128;
if isfield(cfg, "receiverCandidateLimit"), limit = cfg.receiverCandidateLimit; end
[forward, forwardScores] = scfde.equalizers.ch5_dfe_detect( ...
    channel.received, book, channel.impulse, cfg.noiseVariance, limit);
[~, backwardScores] = scfde.equalizers.ch5_backward_dfe_detect( ...
    channel.received, book, channel.impulse, cfg.noiseVariance, limit);
bi1 = scfde.equalizers.ch5_fuse_scores(forwardScores, backwardScores);
detected = scfde.equalizers.ch5_bidirectional_refine( ...
    channel.received, book, channel.impulse, bi1, cfg.noiseVariance, limit);
decisions = cck_indices_to_symbols(detected, source, book);
% Soft chip output: circular matched filter of the received chips
% with the channel (consistent with cck_rake), so the constellation
% shows the soft axial-QPSK chip estimates instead of the hard
% decisions.
softChips = ifft(conj(fft(channel.impulse, numel(channel.received))) .* ...
    fft(channel.received));
receiver = scfde.equalizers.pack_equalizer("CCK-BiDFE-2", "cck-bidfe2", ...
    decisions, zeros(size(decisions)), softChips, ...
    struct("indices", detected, "bi1", bi1, "forward", forward));
end

function decisions = cck_indices_to_symbols(detected, source, book)
blockCount = numel(detected);
dataLength = numel(source.data);
decisions = zeros(1, dataLength);
for block = 1:min(blockCount, floor(dataLength / 8))
    decisions((block - 1) * 8 + (1:8)) = book(detected(block), :);
end
end
