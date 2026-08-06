function gamma = ch4_branch_metrics(codedLlr, nextState, outputBits, logarithmic)
T = numel(codedLlr) / 2;
gamma = zeros(T, size(nextState, 1), 2);
for time = 1:T
    receivedLlr = codedLlr(2 * time - 1:2 * time);
    for state = 1:size(nextState, 1)
        for inputBit = 0:1
            bits = squeeze(outputBits(state, inputBit + 1, :)).';
            value = 0.5 * sum((1 - 2 * bits) .* receivedLlr);
            if logarithmic
                gamma(time, state, inputBit + 1) = value;
            else
                gamma(time, state, inputBit + 1) = exp(max(-50, min(50, value)));
            end
        end
    end
end
end
