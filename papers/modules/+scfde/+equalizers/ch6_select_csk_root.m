function root = ch6_select_csk_root(lengthCode)
%CH6_SELECT_CSK_ROOT Deterministic CSK root sequence (book 6.1).
% Uses a fixed RNG seed so the same codebook is produced on every call,
% keeping transmitter and receiver dictionaries self-consistent.
rng(2024, "twister");
bestScore = inf;
root = ones(1, lengthCode);
for trial = 1:600
    candidate = 2 * randi([0, 1], 1, lengthCode) - 1;
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
root = root / norm(root);
end
