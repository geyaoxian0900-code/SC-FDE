function [book, bits] = ch5_cck_codebook(name, wordLength, unitEnergy)
name = string(name);
switch name
    case {"FR-CCK", "GCCK-QPSK-8R"}
        bitCount = 8;
    case {"HR-CCK", "GCCK-QPSK-4R"}
        bitCount = 4;
    case "GCCK-8PSK-12R"
        bitCount = 12;
    otherwise
        error("SCFDE:UnknownCCK", "Unknown CCK mode: %s", name);
end
M = 2^bitCount;
bits = zeros(M, bitCount);
book = complex(zeros(M, wordLength));
for index = 0:M - 1
    rowBits = bitget(index, 1:bitCount);
    bits(index + 1, :) = rowBits;
    phase = scfde.equalizers.ch5_cck_phases(name, rowBits);
    word = scfde.equalizers.ch5_cck_word(phase);
    if wordLength > 8
        word = extend_scfde.equalizers.ch5_cck_word(word, wordLength, rowBits);
    end
    if unitEnergy
        word = word / sqrt(wordLength);
    else
        word = word / sqrt(8);
    end
    book(index + 1, :) = word;
end
end
