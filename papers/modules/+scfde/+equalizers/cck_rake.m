function receiver = cck_rake(channel, source, cfg)
%CCK_RAKE CCK Rake receiver module (book 5.2.2, 5-17).
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
detected = scfde.equalizers.ch5_rake_detect(channel.received, book, channel.impulse);
decisions = cck_indices_to_symbols(detected, source, book);
% Soft chip output: circular matched filter of the received chips with
% the channel (like the PTR front end), so the constellation shows the
% soft axial-QPSK chip estimates instead of the hard decisions.
N = numel(channel.received);
softChips = ifft(conj(fft(channel.impulse, N)) .* fft(channel.received));
receiver = scfde.equalizers.pack_equalizer("CCK-Rake", "cck-rake", ...
    decisions, zeros(size(decisions)), softChips, ...
    struct("indices", detected, ...
    "formulaStatus", "BOOK-EXACT", ...
    "formulaMode", "book", ...
    "bookExperimentEquivalent", false, ...
    "effectiveParameters", struct("rakeTaps", numel(channel.impulse), ...
        "combining", "maximal ratio h_l* per tap, single codebook decision"), ...
    "formulaNote", "(5-11)/(5-24)/(5-33)~(5-40): per-tap conjugate-gain combining; the chip-domain sum plus one codebook decision is decision-equivalent to argmax_q Re sum_l h_l* <r_tau_l, a_q> (oracle-tested)"));
end

function decisions = cck_indices_to_symbols(detected, source, book)
% Map CCK word indices to a symbol-length output aligned with source.data.
blockCount = numel(detected);
dataLength = numel(source.data);
decisions = zeros(1, dataLength);
for block = 1:min(blockCount, floor(dataLength / 8))
    decisions((block - 1) * 8 + (1:8)) = book(detected(block), :);
end
end
