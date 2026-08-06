function coded = ch4_convolutional_encode(bits)
state = [0, 0];
coded = zeros(1, 2 * numel(bits));
for index = 1:numel(bits)
    inputBit = bits(index);
    coded(2 * index - 1) = mod(inputBit + state(2), 2);
    coded(2 * index) = mod(inputBit + state(1) + state(2), 2);
    state = [inputBit, state(1)];
end
end
