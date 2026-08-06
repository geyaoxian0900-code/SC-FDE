function scores = ch5_feedback_scores(received, book, channel, decisions, noiseVariance, limit)
wordLength = size(book, 2);
memory = numel(channel) - 1;
scores = -inf(numel(decisions), size(book, 1));
state = zeros(1, memory);
for block = 1:numel(decisions)
    observation = received((block - 1) * wordLength + (1:wordLength));
    active = scfde.equalizers.ch5_candidate_list(observation, book, min(limit, size(book, 1)));
    scores(block, active) = scfde.equalizers.ch5_candidate_scores(observation, state, ...
        book(active, :), channel, noiseVariance);
    state = scfde.equalizers.ch5_append_channel_state(state, book(decisions(block), :), memory);
end
end
