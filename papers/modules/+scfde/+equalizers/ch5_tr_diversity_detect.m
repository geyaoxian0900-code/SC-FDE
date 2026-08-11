function detected = ch5_tr_diversity_detect(received, book, channel, noiseVariance)
%CH5_TR_DIVERSITY_DETECT TR-Diversity-2R detection (book 5.4.4).
%   Unifies the unified module with the Chapter-5 suite's
%   tr_diversity_detect: RECEIVED may be a matrix (R x N, one row per
%   true receive branch); every branch passes through the SAME matched
%   filter conj(fliplr(channel)) and the blocks are aligned at the
%   THEORETICAL matched-filter delay (positions = memory + (block-1)*8)
%   - not at max(abs(focused)), whose peak position depends on the CCK
%   data content (the old peak-based alignment selected arbitrary frame
%   positions under multipath and detected ~50% BER).  The FULL
%   convolution keeps the channel tail, so identity frames (8 chips,
%   no tail) and multipath frames both align exactly.
wordLength = size(book, 2);
memory = numel(channel) - 1;
if isvector(received)
    received = received(:).';
end
blockCount = ceil((size(received, 2) - memory) / wordLength);
branchCount = size(received, 1);
combined = complex(zeros(blockCount, wordLength));
for branch = 1:branchCount
    focused = conv(conj(fliplr(channel)), received(branch, :));
    for block = 1:blockCount
        positions = memory + (block - 1) * wordLength + (1:wordLength);
        combined(block, :) = combined(block, :) + focused(positions) / ...
            sum(abs(channel).^2);
    end
end
detected = scfde.equalizers.ch5_nearest_book(combined / branchCount, book);
end
