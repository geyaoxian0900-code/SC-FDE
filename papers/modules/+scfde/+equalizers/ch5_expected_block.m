function output = ch5_expected_block(state, word, channel)
memory = numel(channel) - 1;
convolution = conv([state, word], channel);
output = convolution(memory + 1:memory + numel(word));
end
