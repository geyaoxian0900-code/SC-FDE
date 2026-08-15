function output = ch5_expected_block(state, word, channel)
%CH5_EXPECTED_BLOCK Middle segment of the convolution of [state, word]
% with the channel.  The segment start is determined by the STATE
% LENGTH (not numel(channel)), so zero-memory channels (state = 1x0)
% slice the word's own response head exactly, and padded channel
% vectors ([h, 0, 0]) behave identically to their effective form.
memory = numel(state);
convolution = conv([state, word], channel);
output = convolution(memory + 1:memory + numel(word));
end
