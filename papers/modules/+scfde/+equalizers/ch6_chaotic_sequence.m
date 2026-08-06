function sequence = ch6_chaotic_sequence(lengthCode)
state = 0.173;
for index = 1:128
    state = 4 * state * (1 - state);
end
sequence = zeros(1, lengthCode);
for index = 1:lengthCode
    state = 4 * state * (1 - state);
    sequence(index) = 2 * state - 1;
end
sequence = sequence - mean(sequence);
end
