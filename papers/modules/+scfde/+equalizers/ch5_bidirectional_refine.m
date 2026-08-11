function detected = ch5_bidirectional_refine(received, book, channel, initial, noiseVariance, limit)
%CH5_BIDIRECTIONAL_REFINE Bidirectional score refinement (BiDFE-2).
%   Re-scores every block in BOTH directions using the fused decisions
%   as known channel state, then fuses again.  The reverse pass must
%   use the corrected reverse-stream model (frame-TAIL segment
%   predicted = conj(fliplr(conv([0, word], h)))(1:8) with the
%   following original block's convolution head added to the leading
%   taps); the old version re-ran the FORWARD model on the reversed
%   stream (middle-segment alignment), which detected 27.6% BER under
%   multipath while the forward branch alone was 4.5%.
wordLength = size(book, 2);
memory = numel(channel) - 1;
limit = min(limit, size(book, 1));
forwardScores = -inf(numel(initial), size(book, 1));
state = zeros(1, memory);
for block = 1:numel(initial)
    observation = received((block - 1) * wordLength + (1:wordLength));
    active = scfde.equalizers.ch5_candidate_list(observation, book, limit);
    forwardScores(block, active) = scfde.equalizers.ch5_candidate_scores(observation, state, ...
        book(active, :), channel, noiseVariance);
    state = scfde.equalizers.ch5_append_channel_state(state, book(initial(block), :), memory);
end
reverseReceived = conj(fliplr(received));
revInitial = fliplr(initial);
state = zeros(1, memory);
reverseScores = -inf(numel(initial), size(book, 1));
for block = 1:numel(initial)
    observation = reverseReceived((block - 1) * wordLength + (1:wordLength));
    screenObs = observation;
    if any(state ~= 0)
        screenObs(1:memory) = screenObs(1:memory) - state;
    end
    % Full codebook: the reversed-stream observation is the original
    % block's convolution TAIL segment, whose own tail taps are
    % codeword-dependent and defeat any nearest-neighbour screen.
    active = 1:size(book, 1);
    tailOffset = numel(received) - wordLength * numel(initial);
    local = zeros(1, numel(active));
    for candidate = 1:numel(active)
        full = conv(book(active(candidate), :), channel);
        predicted = conj(fliplr(full(tailOffset + 1:tailOffset + wordLength)));
        if any(state ~= 0)
            predicted(1:memory) = predicted(1:memory) + state;
        end
        local(candidate) = -sum(abs(observation - predicted).^2) / ...
            max(noiseVariance, 1e-8);
    end
    reverseScores(block, active) = local;
    % State update is NOT conditional: reverse block j's observation
    % already contains the convolution head of the ORIGINAL block
    % revInitial(j) (the following block, read backwards), so the state
    % for block j+1 must be computed right after block j.  The previous
    % "if block > 1" version loaded revInitial(block-1) at the START of
    % block 2, so block 2 scored with state = 0 and block 3 reused the
    % state that belonged to block 2 - one-block lag (masked by the
    % forward branch under identity, visible under multipath).
    fullClean = conv(book(revInitial(block), :), channel);
    if numel(fullClean) > wordLength
        state = conj(fliplr(fullClean(1:memory)));
    else
        state = zeros(1, memory);
    end
end
% The reverse pass scores the reversed stream, whose block j is the
% ORIGINAL block N-j+1: flip the rows back to original order before
% fusing (fusing without the flip adds m_i with m_{N-i+1} scores).
detected = scfde.equalizers.ch5_fuse_scores(forwardScores, flipud(reverseScores));
end
