function detected = ch5_fuse_scores(forwardScores, backwardScores)
combined = forwardScores - max(forwardScores, [], 2) + ...
    backwardScores - max(backwardScores, [], 2);
[~, detected] = max(combined, [], 2);
detected = detected.';
end
