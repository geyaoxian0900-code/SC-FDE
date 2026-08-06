function [informationLlr, codedLlr] = ch4_probability_posteriors( ...
        alpha, beta, gamma, nextState, outputBits)
T = size(gamma, 1);
informationLlr = zeros(1, T);
codedLlr = zeros(1, 2 * T);
for time = 1:T
    inputValue = zeros(1, 2);
    codeValue = zeros(2, 2);
    for state = 1:size(nextState, 1)
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            pathMetric = alpha(time, state) * ...
                gamma(time, state, inputBit + 1) * beta(time + 1, next);
            inputValue(inputBit + 1) = inputValue(inputBit + 1) + pathMetric;
            bits = squeeze(outputBits(state, inputBit + 1, :)).';
            for codeIndex = 1:2
                codeValue(bits(codeIndex) + 1, codeIndex) = ...
                    codeValue(bits(codeIndex) + 1, codeIndex) + pathMetric;
            end
        end
    end
    informationLlr(time) = log(max(inputValue(1), realmin)) - ...
        log(max(inputValue(2), realmin));
    codedLlr(2 * time - 1) = log(max(codeValue(1, 1), realmin)) - ...
        log(max(codeValue(2, 1), realmin));
    codedLlr(2 * time) = log(max(codeValue(1, 2), realmin)) - ...
        log(max(codeValue(2, 2), realmin));
end
end
