function frame = ch5_static_cck_frame(book, channel, cfg, snrDb)
frame.indices = randi(size(book, 1), 1, cfg.symbols);
frame.chips = reshape(book(frame.indices, :).', 1, []);
frame.noiseVariance = 10^(-snrDb / 10);
if isfield(cfg, "receiverSnrDefinition") && ...
        strcmpi(string(cfg.receiverSnrDefinition), "EbN0")
    frame.noiseVariance = frame.noiseVariance / log2(size(book, 1));
end
memory = numel(channel) - 1;
if isfield(cfg, "useCyclicPrefix") && cfg.useCyclicPrefix
    transmitted = [frame.chips(end - memory + 1:end), frame.chips];
    channelOutput = filter(channel, 1, transmitted);
    channelOutput = channelOutput(memory + 1:memory + numel(frame.chips));
    channelTail = zeros(1, memory);
else
    channelOutput = filter(channel, 1, [frame.chips, zeros(1, memory)]);
    channelTail = zeros(1, 0);
end
receivedLength = numel(channelOutput) + numel(channelTail);
frame.received = [channelOutput channelTail] + ...
    sqrt(frame.noiseVariance / 2) * ...
    (randn(1, receivedLength) + 1j * randn(1, receivedLength));
end
