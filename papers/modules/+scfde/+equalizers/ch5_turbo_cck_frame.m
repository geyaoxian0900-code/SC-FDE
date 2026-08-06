function frame = ch5_turbo_cck_frame(book, bits, channel, cfg, snrDb)
bitCount = size(bits, 2);
codedLength = cfg.symbols * bitCount;
assert(mod(codedLength, 2) == 0, "SCFDE:InvalidTurboFrame", ...
    "symbols times bits per CCK word must be even for repetition-1/2.");
informationLength = codedLength / 2;
frame.informationBits = randi([0, 1], 1, informationLength);
positions = randperm(codedLength);
frame.firstCopy = positions(1:informationLength);
secondCopy = positions(informationLength + 1:end);
interleaver = randperm(informationLength);
frame.codedBits = zeros(1, codedLength);
frame.codedBits(frame.firstCopy) = frame.informationBits;
frame.codedBits(secondCopy) = frame.informationBits(interleaver);
inverseInterleaver = zeros(1, informationLength);
inverseInterleaver(interleaver) = 1:informationLength;
frame.pairedPosition = zeros(1, codedLength);
frame.pairedPosition(frame.firstCopy) = secondCopy(inverseInterleaver);
frame.pairedPosition(secondCopy) = frame.firstCopy(interleaver);
wordBits = reshape(frame.codedBits, bitCount, []).';
frame.indices = (1 + wordBits * (2 .^ (0:bitCount - 1)).').';
frame.chips = reshape(book(frame.indices, :).', 1, []);
frame.noiseVariance = 10^(-snrDb / 10);
memory = numel(channel) - 1;
frame.received = filter(channel, 1, [frame.chips, zeros(1, memory)]) + ...
    sqrt(frame.noiseVariance / 2) * ...
    (randn(1, numel(frame.chips) + memory) + ...
    1j * randn(1, numel(frame.chips) + memory));
end
