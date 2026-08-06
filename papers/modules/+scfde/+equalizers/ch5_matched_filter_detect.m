function detected = ch5_matched_filter_detect(received, book, channel)
memory = numel(channel) - 1;
focused = filter(conj(fliplr(channel)), 1, received);
aligned = focused(memory + (1:(numel(received) - memory)));
blockCount = floor(numel(aligned) / size(book, 2));
blocks = reshape(aligned(1:blockCount * size(book, 2)), size(book, 2), []).';
detected = scfde.equalizers.ch5_nearest_book(blocks, book);
end
