function detected = ch5_matched_filter_detect(received, book, channel)
%CH5_MATCHED_FILTER_DETECT Matched-filter CCK detection (MFB structure).
%   The matched filter is the FULL convolution
%   conv(conj(fliplr(channel)), received): filter() truncates the
%   output to the input length, so a single 8-chip codeword lost its
%   channel tail and aligned to only 6 samples (blockCount 0 -> no
%   detection).  conv() keeps the full 2*memory extra samples, the
%   middle segment recovers the 8 aligned chips.  The decision is the
%   (5-24) nearest-codebook ML on the CMF output
%   ((5-40)~(5-43): y_k = a_k + pre/post ISI + mu; the matched-filter
%   bound receiver), audited BOOK-EXACT for the CMF chain.
memory = numel(channel) - 1;
wordLength = size(book, 2);
focused = conv(conj(fliplr(channel)), received);
aligned = focused(memory + (1:numel(received)));
blockCount = ceil(numel(aligned) / wordLength);
padded = [aligned, zeros(1, blockCount * wordLength - numel(aligned))];
blocks = reshape(padded, wordLength, []).';
detected = scfde.equalizers.ch5_nearest_book(blocks, book);
end
