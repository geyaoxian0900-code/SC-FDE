function sequence = ch6_m_sequence63(exponents)
sequenceLength = 63;
order = 6;
bits = ones(1, sequenceLength);
for index = 1:sequenceLength - order
    bits(index + order) = mod(sum(bits(index + [0, exponents])), 2);
end
sequence = 1 - 2 * bits;
end
