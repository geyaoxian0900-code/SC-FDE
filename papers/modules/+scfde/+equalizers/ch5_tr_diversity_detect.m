function detected = ch5_tr_diversity_detect(received, book, channel, noiseVariance)
wordLength = size(book, 2);
memory = numel(channel) - 1;
channels = [channel; conj(fliplr(channel))];
combined = zeros(1, numel(received));
for branch = 1:2
    focused = filter(conj(fliplr(channels(branch, :))), 1, received);
    delay = numel(channel) - 1;
    alignedLength = numel(received) - delay;
    combined(1:alignedLength) = combined(1:alignedLength) + ...
        focused(delay + (1:alignedLength)) / ...
        sum(abs(channels(branch, :)).^2);
end
usable = floor((numel(received) - memory) / wordLength) * wordLength;
combined = combined(1:usable);
blocks = reshape(combined / 2, wordLength, []).';
detected = scfde.equalizers.ch5_nearest_book(blocks, book);
end
