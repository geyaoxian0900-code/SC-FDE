function detected = ch5_fuse_scores(forwardScores, backwardScores)
%CH5_FUSE_SCORES Fuse forward and backward candidate scores.
%   ch5_backward_dfe_detect returns scores in ORIGINAL block order
%   (verified: its row j scores the codeword of block j, not block
%   N-j+1 - the module converts back internally).  A flipud here
%   double-reversed the blocks and broke the identity+zero-noise audit
%   (BiDFE-1 0 -> 0.42), so no reordering is applied.
combined = forwardScores - max(forwardScores, [], 2) + ...
    backwardScores - max(backwardScores, [], 2);
[~, detected] = max(combined, [], 2);
detected = detected.';
end
