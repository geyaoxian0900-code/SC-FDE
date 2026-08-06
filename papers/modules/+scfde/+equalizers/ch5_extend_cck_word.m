function word = ch5_extend_cck_word(baseWord, wordLength, bits)
%CH5_EXTEND_CCK_WORD Extend an 8-chip CCK word to 16/32 chips using the
% Golay complementary-pair recurrence (book 5-8/5-9). The sign pattern is
% selected by the input bits, and each 8-chip block is multiplied by it.
blocks = wordLength / 8;
levels = log2(blocks) - 1;
[A, B] = scfde.equalizers.ch5_golay_complementary_pair(levels);
if blocks == 2
    if bits(3) == 0, signs = A; else, signs = B; end
else
    patternIndex = 1 + bits(3) + 2 * bits(4);
    if patternIndex == 1, signs = A; else, signs = B; end
end
word = repmat(baseWord, 1, blocks);
word = word .* repelem(signs, 8);
end
