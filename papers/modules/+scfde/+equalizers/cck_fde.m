function receiver = cck_fde(channel, source, cfg)
%CCK_FDE CCK frequency-domain IBDFE receiver module (book 5.5.2, 5-80).
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
iterations = 2;
if isfield(cfg, "turboIterations"), iterations = cfg.turboIterations; end
[detected, history] = scfde.equalizers.ch5_fde_cck_detect( ...
    channel.received, book, channel.impulse, cfg.noiseVariance, iterations);
decisions = cck_indices_to_symbols(detected, source, book);
% Soft chip output: circular matched filter of the received chips
% with the channel (consistent with cck_rake), so the constellation
% shows the soft axial-QPSK chip estimates instead of the hard
% decisions.
softChips = ifft(conj(fft(channel.impulse, numel(channel.received))) .* ...
    fft(channel.received));
receiver = scfde.equalizers.pack_equalizer("CCK-FDE-IBDFE", "cck-fde", ...
    decisions, zeros(size(decisions)), softChips, ...
    struct("history", history, "indices", detected));
end

function decisions = cck_indices_to_symbols(detected, source, book)
blockCount = numel(detected);
dataLength = numel(source.data);
decisions = zeros(1, dataLength);
for block = 1:min(blockCount, floor(dataLength / 8))
    decisions((block - 1) * 8 + (1:8)) = book(detected(block), :);
end
end
