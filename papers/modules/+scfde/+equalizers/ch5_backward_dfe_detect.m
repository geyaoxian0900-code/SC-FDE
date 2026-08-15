function [detected, scores, soft] = ch5_backward_dfe_detect(received, book, channel, noiseVariance, limit) %#ok<INUSD>
%CH5_BACKWARD_DFE_DETECT Time-reversed DFE on the CCK stream.
%
% LIMIT is part of the shared detector interface (the forward detector
% uses a candidate-list screen) but the reverse path scores the FULL
% codebook, so it is unused here.
%
% The reversed stream block j equals the ORIGINAL block (N-j+1) with
% its chips reversed:  obs_j = conj(fliplr(block m')) where block m'
% is the ORIGINAL transmitted codeword block.  The prediction model
% must therefore use the ORIGINAL codebook and the REVERSED
% convolution
%       pred_j(cand) = conj(fliplr(conv([state, book(cand,:)], channel)))  (first 8)
% NOT conv(..., conj(fliplr(channel))) over the reversed codebook
% (fliplr(conv(a,b)) ~= conv(fliplr(a),fliplr(b)); the fliplr-channel
% model plus the reversed codebook double-reversed the codeword and
% the reverse path detected the wrong indices - identity+zero-noise
% reverse BER ~0.39-0.42 while a nearest-codeword oracle is exact).
%
% DETECTED/SCORES are returned in ORIGINAL block order (fliplr/flipud
% applied before returning).  SOFT is the chip-level reversed-domain DFE
% soft output: row j is the reversed-stream window for reversed block j
% (observation minus the reversed-domain state spill), RAW - neither the
% block order nor the chips are restored here.  Use
% ch5_tr_diversity_restore to map SOFT back to the original time order
% for the (5-57) merge.
wordLength = size(book, 2);
% Full codeword blocks: ceil covers the last block even when the
% channel-tail overlap leaves fewer than memory samples at the end
% (identity channels then detect all blocks instead of one fewer).
% The block count follows the FRAME convention (numel(channel) tail
% samples in the received frame).
blockCount = ceil((numel(received) - numel(channel) + 1) / wordLength);
% Effective channel memory: the LAST NONZERO tap.  Trailing zeros do
% not create channel memory: [1], [1,0] and [1,0,0] must behave as
% zero-memory channels (the previous numel-based memory turned the
% zero-padding into a phantom 2-tap inter-block state).  The FULL
% channel vector is still used for every convolution; only the state
% length (and the state spill window) uses the effective tail.
lastTap = find(channel ~= 0, 1, "last");
if isempty(lastTap)
    lastTap = numel(channel);
end
memory = lastTap - 1;
reverseReceived = conj(fliplr(received));
state = zeros(1, memory);
detected = zeros(1, blockCount);
scores = -inf(blockCount, size(book, 1));
soft = complex(zeros(blockCount, wordLength));
for block = 1:blockCount
    observation = reverseReceived((block - 1) * wordLength + (1:wordLength));
    % The candidate list must be computed in the OBSERVATION domain:
    % the reversed observation resembles the REVERSED codebook rows
    % (reverseBook), not the original rows - a forward-domain candidate
    % list can exclude the true codeword (the identity+zero-noise
    % reverse misses).  The row indices of reverseBook equal the
    % original book indices, so the selected candidates are used with
    % the original codebook for the prediction.
    % Time-reversed (5-47) soft output: remove the reversed-domain
    % state spill (the following original block's head, read backwards)
    % from the observation; the current reversed block's own decision is
    % NOT fed back into its own output.  Captured before the state
    % update, mirroring ch5_dfe_detect.
    statePadded = zeros(1, wordLength);
    statePadded(1:memory) = state;
    soft(block, :) = observation - statePadded;
    % The reversed-stream observation is the FRAME-TAIL segment of the
    % original block's convolution (5:12), which includes the block's
    % OWN tail taps (9:12).  Those taps are codeword-dependent, so no
    % pre-screen can remove them: a nearest-neighbour screen over the
    % reversed codebook rows drops the true codeword under multipath
    % (verified: true index outside the top-128 list on blocks 2-8).
    % The reverse path therefore scores ALL codebook rows.
    active = 1:size(book, 1);
    local = zeros(1, numel(active));
    % The reversed stream reads the frame from its TAIL: block j
    % observes the ORIGINAL block (N-j+1) convolution segment starting
    % tailOffset = numel(received) - wordLength*blockCount samples into
    % the block's own convolution (a multipath frame carries memory
    % tail samples, so the segment is (5:12) - the flipped first
    % wordLength taps of the full convolution; an identity frame has no
    % tail, so the segment is the block itself (1:8) and flipping the
    % full convolution would pick up the channel's zero padding -
    % reverse path detected 0/2700 blocks identity, 5 lengths x 100
    % seeds, while multipath (with its tail) masked the bug).
    tailOffset = numel(received) - wordLength * blockCount;
    for candidate = 1:numel(active)
        full = conv(book(active(candidate), :), channel);
        predicted = conj(fliplr(full(tailOffset + 1:tailOffset + wordLength)));
        % The ORIGINAL following block's convolution head (1:memory)
        % spills into this window's last taps and, after the reversal,
        % lands in the FIRST memory taps of the observation.
        if any(state ~= 0)
            predicted(1:memory) = predicted(1:memory) + state;
        end
        local(candidate) = -sum(abs(observation - predicted).^2) / ...
            max(noiseVariance, 1e-8);
    end
    scores(block, active) = local;
    [~, best] = max(local);
    detected(block) = active(best);
    % Reverse-domain state: the convolution head of the current
    % ORIGINAL codeword (the following block, read backwards) as it
    % appears in the next observation's leading taps.  Only channels
    % with a non-trivial tail spread the following block into the
    % window (identity channels have no inter-block spill: state = 0).
    fullClean = conv(book(detected(block), :), channel);
    if numel(fullClean) > wordLength
        state = conj(fliplr(fullClean(1:memory)));
    else
        state = zeros(1, memory);
    end
end
detected = fliplr(detected);
scores = flipud(scores);
% SOFT deliberately stays in reversed-block order (raw reversed domain):
% the (5-57) time-order restoration is a separate, independently tested
% step (ch5_tr_diversity_restore).
end
