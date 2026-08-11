function detected = ch5_tr_diversity_detect(received, book, channel, noiseVariance)
wordLength = size(book, 2);
memory = numel(channel) - 1;
channels = [channel; conj(fliplr(channel))];
combined = zeros(1, numel(received));
for branch = 1:2
    focused = filter(conj(fliplr(channels(branch, :))), 1, received);
    % Each branch's focused output peaks at its OWN position: the
    % forward branch is delayed by memory while the reversed branch is
    % not.  A single shared delay misaligned the reversed branch and
    % mixed neighbouring codeword chips (identity block 1 became a
    % diagonal mixture -> tr-diversity identity BER ~0.42).
    [~, peak] = max(abs(focused));
    delay = peak - 1;
    alignedLength = numel(received) - delay;
    combined(1:alignedLength) = combined(1:alignedLength) + ...
        focused(delay + (1:alignedLength)) / ...
        sum(abs(channels(branch, :)).^2);
end
usable = min(numel(received), ceil((numel(received) - memory) / wordLength) * wordLength);
combined = combined(1:usable);
blocks = reshape(combined / 2, wordLength, []).';
detected = scfde.equalizers.ch5_nearest_book(blocks, book);
end
