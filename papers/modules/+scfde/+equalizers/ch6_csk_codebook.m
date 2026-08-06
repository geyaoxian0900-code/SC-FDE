function [book, bits] = ch6_csk_codebook(root, M)
bitCount = round(log2(M));
bits = scfde.equalizers.ch6_bit_table(M, bitCount);
book = complex(zeros(M, numel(root)));
for index = 0:M - 1
    book(index + 1, :) = circshift(root, index);
end
end
