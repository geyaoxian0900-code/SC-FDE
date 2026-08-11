function receiver = cck_tr_diversity(channel, source, cfg)
%CCK_TR_DIVERSITY CCK time-reversal diversity receiver (book 5.4.4, 2-47).
% Delegates to the book reference tr_diversity_detect so the output is
% bit-identical to static_receiver_frame's TR-Diversity-2R method.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
nv = cfg.noiseVariance;
if ~isfield(cfg, "noiseVariance") || isempty(nv) || nv <= 0
    nv = 10^(-cfg.snrDb / 10);
end
detected = scfde.equalizers.ch5_tr_diversity_detect( ...
    channel.received, book, channel.impulse, nv);
decisions = cck_indices_to_symbols(detected, source, book);
% Soft chip output: circular matched filter of the received chips
% with the channel (consistent with cck_rake), so the constellation
% shows the soft axial-QPSK chip estimates instead of the hard
% decisions.
softChips = ifft(conj(fft(channel.impulse, numel(channel.received))) .* ...
    fft(channel.received));
receiver = scfde.equalizers.pack_equalizer("CCK-TR-Diversity", ...
    "cck-tr-diversity", decisions, zeros(size(decisions)), softChips, ...
    struct("indices", detected));
end

function decisions = cck_indices_to_symbols(detected, source, book)
blockCount = numel(detected);
dataLength = numel(source.data);
decisions = zeros(1, dataLength);
for block = 1:min(blockCount, floor(dataLength / 8))
    decisions((block - 1) * 8 + (1:8)) = book(detected(block), :);
end
end
