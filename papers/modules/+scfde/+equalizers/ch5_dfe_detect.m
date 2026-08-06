function [detected, scores] = ch5_dfe_detect(received, book, channel, noiseVariance, limit)
wordLength = size(book, 2);
blockCount = floor((numel(received) - numel(channel) + 1) / wordLength);
memory = numel(channel) - 1;
state = zeros(1, memory);
detected = zeros(1, blockCount);
scores = -inf(blockCount, size(book, 1));
for block = 1:blockCount
    observation = received((block - 1) * wordLength + (1:wordLength));
    active = scfde.equalizers.ch5_candidate_list(observation, book, min(limit, size(book, 1)));
    local = scfde.equalizers.ch5_candidate_scores(observation, state, book(active, :), channel, noiseVariance);
    scores(block, active) = local;
    [~, best] = max(local);
    detected(block) = active(best);
    state = scfde.equalizers.ch5_append_channel_state(state, book(detected(block), :), memory);
end
end
