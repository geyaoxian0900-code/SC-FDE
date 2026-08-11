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
    % Under multipath the observation's leading taps also carry the
    % KNOWN spill of the following ORIGINAL block (the state); remove
    % it before the nearest-neighbour screen, or the true codeword
    % falls out of the top-`limit` list (multipath reverse misses).
    screenObs = observation;
    if any(state ~= 0)
        screenObs(1:memory) = screenObs(1:memory) - state;
    end
    % The reversed-stream observation is the FRAME-TAIL segment of the
    % original block's convolution (5:12), which includes the block's
    % OWN tail taps (9:12).  Those taps are codeword-dependent, so no
    % pre-screen can remove them: a nearest-neighbour screen over the
    % reversed codebook rows drops the true codeword under multipath
    % (verified: true index outside the top-128 list on blocks 2-8).
    % The reverse path therefore scores ALL codebook rows.
    active = 1:size(book, 1);
    local = zeros(1, numel(active));
    for candidate = 1:numel(active)
        full = conv([zeros(1, memory), book(active(candidate), :)], channel);
        predicted = conj(fliplr(full));
        % The reversed stream reads the frame from its TAIL: block j
        % observes the ORIGINAL block (N-j+1) convolution segment
        % (5:12) (the frame-tail offset), so after the reversal the
        % predicted block sits in the FIRST wordLength samples, not the
        % middle (the middle segment is the frame-HEAD model used by
        % the forward DFE and mismatches the tail by 4 samples - the
        % multipath reverse path detected 160/160 wrong blocks while
        % identity stayed exact).
        predicted = predicted(1:wordLength);
        % The ORIGINAL following block's convolution head (1:memory)
        % spills into this window's last taps and, after the reversal,
        % lands in the FIRST memory taps of the observation.
        if numel(state) == memory && any(state ~= 0)
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
end
