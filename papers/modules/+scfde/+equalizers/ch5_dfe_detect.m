function [detected, scores, soft] = ch5_dfe_detect(received, book, channel, noiseVariance, limit)
%CH5_DFE_DETECT Forward DFE on the CCK stream (book (5-46)/(5-47) path).
%   DETECTED: 1 x blockCount codeword indices (original block order).
%   SCORES:   blockCount x codebookSize candidate log-likelihoods.
%   SOFT:     blockCount x wordLength chip-level DFE soft output, i.e. the
%             temporary-decision output of (5-47): observation minus the
%             ISI of the PAST temporary decisions (the state spill into
%             this window), captured BEFORE the current block's own
%             decision is fed back.  Row `block` corresponds to original
%             block `block`; under an identity channel SOFT equals the
%             received chips.  Added for the (5-57) time-reversal
%             diversity merge in cck_tr_diversity.
wordLength = size(book, 2);
% Full codeword blocks: ceil covers the last block even when the
% channel-tail overlap leaves fewer than memory samples at the end
% (identity channels then detect all blocks instead of one fewer).
% The block count follows the FRAME convention (numel(channel) tail
% samples in the received frame).
blockCount = ceil((numel(received) - numel(channel) + 1) / wordLength);
% Effective channel memory: the LAST NONZERO tap.  Trailing zeros do
% not create channel memory, so [1], [1,0] and [1,0,0] all behave as
% zero-memory channels; the FULL channel vector is still used for all
% convolutions, only the state length is reduced.
lastTap = find(channel ~= 0, 1, "last");
if isempty(lastTap)
    lastTap = numel(channel);
end
memory = lastTap - 1;
state = zeros(1, memory);
detected = zeros(1, blockCount);
scores = -inf(blockCount, size(book, 1));
soft = complex(zeros(blockCount, wordLength));
for block = 1:blockCount
    observation = received((block - 1) * wordLength + (1:wordLength));
    % (5-47) soft DFE output: remove the past-decision state spill only;
    % the current block's response (including its intra-block ISI) stays,
    % and the block's own decision is NOT fed back into its own output.
    soft(block, :) = observation - scfde.equalizers.ch5_expected_block( ...
        state, zeros(1, wordLength), channel);
    active = scfde.equalizers.ch5_candidate_list(observation, book, min(limit, size(book, 1)));
    local = scfde.equalizers.ch5_candidate_scores(observation, state, book(active, :), channel, noiseVariance);
    scores(block, active) = local;
    [~, best] = max(local);
    detected(block) = active(best);
    state = scfde.equalizers.ch5_append_channel_state(state, book(detected(block), :), memory);
end
end
