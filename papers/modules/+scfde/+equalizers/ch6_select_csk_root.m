function root = ch6_select_csk_root(lengthCode)
%CH6_SELECT_CSK_ROOT Deterministic CSK root sequence (book 6.1).
% Uses a LOCAL seeded RandStream (not the global rng) so the same
% codebook is produced on every call while the caller's global RNG
% state is untouched: transmitter and receiver dictionaries stay
% self-consistent AND the equalizer wrappers remain RNG-transparent.
%
% The root is returned as the raw +/-1 sequence (energy G), matching the
% book (6-5)/(6-7) normalization: the 1/G correlation of a +/-1 sequence
% has main peak exactly 1.  The dictionary builders renormalize rows to
% unit energy (ch6_apply_circular_channel scale), an exact scale-
% invariant mapping - the dictionary-domain decisions are unaffected
% while the raw-chip outputs follow the book chip alphabet.
stream = RandStream("mt19937ar", "Seed", 2024);
bestScore = inf;
root = ones(1, lengthCode);
for trial = 1:600
    candidate = 2 * randi(stream, [0, 1], 1, lengthCode) - 1;
    if abs(sum(candidate)) > 2
        continue;
    end
    correlation = abs(ifft(abs(fft(candidate)).^2)) / lengthCode;
    score = max(correlation(2:end));
    if score < bestScore
        bestScore = score;
        root = candidate;
    end
end
% NOTE: no unit-norm normalization here (strict book +/-1 convention);
% energy normalization happens in the dictionary domain only.
end
