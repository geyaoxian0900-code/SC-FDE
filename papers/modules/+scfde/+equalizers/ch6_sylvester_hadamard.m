function H = ch6_sylvester_hadamard(lengthCode)
stageCount = round(log2(lengthCode));
H = zeros(lengthCode);
for row = 0:lengthCode - 1
    for column = 0:lengthCode - 1
        parity = 0;
        overlap = bitand(row, column);
        for stage = 1:stageCount
            parity = parity + bitget(overlap, stage);
        end
        H(row + 1, column + 1) = (-1)^parity;
    end
end
end
