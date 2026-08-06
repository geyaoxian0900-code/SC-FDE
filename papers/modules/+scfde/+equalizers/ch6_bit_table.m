function bits = ch6_bit_table(M, bitCount)
bits = zeros(M, bitCount);
for index = 0:M - 1
    bits(index + 1, :) = bitget(index, 1:bitCount);
end
end
