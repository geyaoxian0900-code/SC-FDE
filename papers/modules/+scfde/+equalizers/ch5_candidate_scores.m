function scores = ch5_candidate_scores(observation, state, candidates, channel, noiseVariance)
scores = zeros(1, size(candidates, 1));
for index = 1:size(candidates, 1)
    predicted = scfde.equalizers.ch5_expected_block(state, candidates(index, :), channel);
    scores(index) = -sum(abs(observation - predicted).^2) / max(noiseVariance, 1e-8);
end
end
