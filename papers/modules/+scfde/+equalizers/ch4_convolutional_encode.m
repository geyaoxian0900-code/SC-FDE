function coded = ch4_convolutional_encode(bits)
% Convolutional encoder with generators (G1, G2) = (7, 5) octal.
%   G1 = 111b : c1 = u xor s1 xor s2
%   G2 = 101b : c2 = u xor s2
% State is [s1, s2] with s1 the most recent input.
state = [0, 0];
coded = zeros(1, 2 * numel(bits));
for index = 1:numel(bits)
    inputBit = bits(index);
    coded(2 * index - 1) = mod(inputBit + state(1) + state(2), 2);
    coded(2 * index) = mod(inputBit + state(2), 2);
    state = [inputBit, state(1)];
end
end
