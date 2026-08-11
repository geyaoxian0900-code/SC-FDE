function [detected, scores] = ch5_backward_dfe_detect(received, book, channel, noiseVariance, limit)
%CH5_BACKWARD_DFE_DETECT Time-reversed DFE on the CCK stream.
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
wordLength = size(book, 2);
% Full codeword blocks: ceil covers the last block even when the
        % channel-tail overlap leaves fewer than memory samples at the
        % end (identity channels then detect all 8 blocks instead of 7).
        blockCount = ceil((numel(received) - numel(channel) + 1) / wordLength);
memory = numel(channel) - 1;
reverseReceived = conj(fliplr(received));
state = zeros(1, memory);
detected = zeros(1, blockCount);
scores = -inf(blockCount, size(book, 1));
for block = 1:blockCount
    observation = reverseReceived((block - 1) * wordLength + (1:wordLength));
    % The candidate list must be computed in the OBSERVATION domain:
    % the reversed observation resembles the REVERSED codebook rows
    % (reverseBook), not the original rows - a forward-domain candidate
    % list can exclude the true codeword (the identity+zero-noise
    % reverse misses).  The row indices of reverseBook equal the
    % original book indices, so the selected candidates are used with
    % the original codebook for the prediction.
    active = scfde.equalizers.ch5_candidate_list(observation, ...
        conj(fliplr(book)), min(limit, size(book, 1)));
    local = zeros(1, numel(active));
    for candidate = 1:numel(active)
        full = conv([state, book(active(candidate), :)], channel);
        predicted = conj(fliplr(full));
        % The original block's 8 samples are the middle segment of the
        % convolution; after reversal they sit at (memory+1 : memory+8).
        predicted = predicted(memory + 1:memory + wordLength);
        local(candidate) = -sum(abs(observation - predicted).^2) / ...
            max(noiseVariance, 1e-8);
    end
    scores(block, active) = local;
    [~, best] = max(local);
    detected(block) = active(best);
    % Reverse-domain state: the channel tail of the current ORIGINAL
    % codeword as it appears at the head of the reversed stream
    % (fliplr(full)(1:memory)).
    full = conv([state, book(detected(block), :)], channel);
    reversed = conj(fliplr(full));
    state = reversed(1:memory);
end
detected = fliplr(detected);
scores = flipud(scores);
end
