function state = ch5_append_channel_state(state, samples, memory)
combined = [state, samples];
state = combined(end - memory + 1:end);
end
