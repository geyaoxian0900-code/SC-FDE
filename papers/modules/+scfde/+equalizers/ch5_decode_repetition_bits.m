function informationBits = ch5_decode_repetition_bits(codedBits, frame)
informationBits = codedBits(frame.firstCopy);
pairedBits = codedBits(frame.pairedPosition(frame.firstCopy));
agreement = informationBits == pairedBits;
informationBits(agreement) = pairedBits(agreement);
end
