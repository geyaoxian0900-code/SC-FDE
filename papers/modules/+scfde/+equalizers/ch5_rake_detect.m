function detected = ch5_rake_detect(received, book, channel)
wordLength = size(book, 2);
% ceil covers the last block when the channel-tail overlap leaves fewer
% than numel(channel) samples at the end (identity channels then
% detect all 8 blocks instead of 7).
blockCount = ceil((numel(received) - numel(channel) + 1) / wordLength);
padded = [received, zeros(1, numel(channel))];
combined = complex(zeros(blockCount, wordLength));
for block = 1:blockCount
    start = (block - 1) * wordLength + 1;
    for tap = 1:numel(channel)
        combined(block, :) = combined(block, :) + conj(channel(tap)) * ...
            padded(start + tap - 1:start + tap + wordLength - 2);
    end
end
detected = scfde.equalizers.ch5_nearest_book(combined / max(sum(abs(channel).^2), 1e-8), book);
end
