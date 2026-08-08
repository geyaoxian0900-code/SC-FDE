function [nextState, outputBits] = ch4_convolutional_trellis()
% Trellis for generators (G1, G2) = (7, 5) octal:
%   c1 = u xor s1 xor s2,  c2 = u xor s2
% (matches ch4_convolutional_encode).
nextState = zeros(4, 2);
outputBits = zeros(4, 2, 2);
for state = 0:3
    memory = [bitget(state, 2), bitget(state, 1)];
    for inputBit = 0:1
        nextState(state + 1, inputBit + 1) = inputBit * 2 + memory(1) + 1;
        outputBits(state + 1, inputBit + 1, :) = [ ...
            mod(inputBit + memory(1) + memory(2), 2), ...
            mod(inputBit + memory(2), 2)];
    end
end
end
