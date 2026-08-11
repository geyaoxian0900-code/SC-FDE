function receiver = cck_mfb(channel, source, cfg)
%CCK_MFB CCK matched-filter bound receiver (MFB).
% Equivalent to matched_filter_detect in static_receiver_frame.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
detected = scfde.equalizers.ch5_matched_filter_detect( ...
    channel.received, book, channel.impulse);
decisions = cck_indices_to_symbols(detected, source, book);
% Soft chip output: circular matched filter of the received chips
% with the channel (consistent with cck_rake), so the constellation
% shows the soft axial-QPSK chip estimates instead of the hard
% decisions.
softChips = ifft(conj(fft(channel.impulse, numel(channel.received))) .* ...
    fft(channel.received));
receiver = scfde.equalizers.pack_equalizer("CCK-MFB", "cck-mfb", ...
    decisions, zeros(size(decisions)), softChips, struct("indices", detected));
end

function decisions = cck_indices_to_symbols(detected, source, book)
blockCount = numel(detected);
dataLength = numel(source.data);
decisions = zeros(1, dataLength);
for block = 1:min(blockCount, floor(dataLength / 8))
    decisions((block - 1) * 8 + (1:8)) = book(detected(block), :);
end
end
