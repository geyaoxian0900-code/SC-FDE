function [informationLlr, codedLlr, alpha] = ch4_bcjr_log_domain(codedLlr, mode)
T = numel(codedLlr) / 2;
stateCount = 4;
[nextState, outputBits] = scfde.equalizers.ch4_convolutional_trellis();
gamma = scfde.equalizers.ch4_branch_metrics(codedLlr, nextState, outputBits, true);
alpha = -inf(T + 1, stateCount);
beta = -inf(T + 1, stateCount);
alpha(1, 1) = 0;
beta(T + 1, :) = 0;
for time = 1:T
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            alpha(time + 1, next) = scfde.equalizers.ch4_log_combine(alpha(time + 1, next), ...
                alpha(time, state) + gamma(time, state, inputBit + 1), mode);
        end
    end
    alpha(time + 1, :) = scfde.equalizers.ch4_normalize_log_row(alpha(time + 1, :));
end
for time = T:-1:1
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            beta(time, state) = scfde.equalizers.ch4_log_combine(beta(time, state), ...
                gamma(time, state, inputBit + 1) + beta(time + 1, next), mode);
        end
    end
    beta(time, :) = scfde.equalizers.ch4_normalize_log_row(beta(time, :));
end
informationLlr = zeros(1, T);
codedLlr = zeros(1, 2 * T);
for time = 1:T
    inputValue = [-inf, -inf];
    codeValue = -inf(2, 2);
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            pathMetric = alpha(time, state) + ...
                gamma(time, state, inputBit + 1) + beta(time + 1, next);
            inputValue(inputBit + 1) = scfde.equalizers.ch4_log_combine( ...
                inputValue(inputBit + 1), pathMetric, mode);
            bits = squeeze(outputBits(state, inputBit + 1, :)).';
            for codeIndex = 1:2
                codeValue(bits(codeIndex) + 1, codeIndex) = scfde.equalizers.ch4_log_combine( ...
                    codeValue(bits(codeIndex) + 1, codeIndex), pathMetric, mode);
            end
        end
    end
    informationLlr(time) = inputValue(1) - inputValue(2);
    codedLlr(2 * time - 1) = codeValue(1, 1) - codeValue(2, 1);
    codedLlr(2 * time) = codeValue(1, 2) - codeValue(2, 2);
end
end
