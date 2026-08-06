function detected = ch5_genie_ch5_dfe_detect(received, chips, book, channel, noiseVariance, limit)
wordLength = size(book, 2);
blockCount = floor(numel(chips) / wordLength);
memory = numel(channel) - 1;
state = zeros(1, memory);
detected = zeros(1, blockCount);
for block = 1:blockCount
    observation = received((block - 1) * wordLength + (1:wordLength));
    active = scfde.equalizers.ch5_candidate_list(observation, book, min(limit, size(book, 1)));
    score = scfde.equalizers.ch5_candidate_scores(observation, state, book(active, :), channel, noiseVariance);
    [~, best] = max(score);
    detected(block) = active(best);
    known = chips((block - 1) * wordLength + (1:wordLength));
    state = scfde.equalizers.ch5_append_channel_state(state, known, memory);
end
end
