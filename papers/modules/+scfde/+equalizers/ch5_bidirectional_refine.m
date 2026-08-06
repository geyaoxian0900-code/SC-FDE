function detected = ch5_bidirectional_refine(received, book, channel, initial, noiseVariance, limit)
wordLength = size(book, 2);
memory = numel(channel) - 1;
forwardScores = -inf(numel(initial), size(book, 1));
state = zeros(1, memory);
for block = 1:numel(initial)
    observation = received((block - 1) * wordLength + (1:wordLength));
    active = scfde.equalizers.ch5_candidate_list(observation, book, min(limit, size(book, 1)));
    forwardScores(block, active) = scfde.equalizers.ch5_candidate_scores(observation, state, ...
        book(active, :), channel, noiseVariance);
    state = scfde.equalizers.ch5_append_channel_state(state, book(initial(block), :), memory);
end
reverseScores = scfde.equalizers.ch5_feedback_scores(conj(fliplr(received)), conj(fliplr(book)), ...
    conj(fliplr(channel)), fliplr(initial), noiseVariance, limit);
detected = scfde.equalizers.ch5_fuse_scores(forwardScores, flipud(reverseScores));
end
