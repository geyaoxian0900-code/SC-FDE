function [informationLlr, codedLlr, alpha] = ch4_bcjr_probability(codedLlr)
T = numel(codedLlr) / 2;
stateCount = 4;
[nextState, outputBits] = scfde.equalizers.ch4_convolutional_trellis();
gamma = scfde.equalizers.ch4_branch_metrics(codedLlr, nextState, outputBits, false);
alpha = zeros(T + 1, stateCount);
beta = zeros(T + 1, stateCount);
alpha(1, 1) = 1;
beta(T + 1, :) = 1 / stateCount;
for time = 1:T
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            alpha(time + 1, next) = alpha(time + 1, next) + ...
                alpha(time, state) * gamma(time, state, inputBit + 1);
        end
    end
    alpha(time + 1, :) = alpha(time + 1, :) / ...
        max(sum(alpha(time + 1, :)), realmin);
end
for time = T:-1:1
    for state = 1:stateCount
        for inputBit = 0:1
            next = nextState(state, inputBit + 1);
            beta(time, state) = beta(time, state) + ...
                gamma(time, state, inputBit + 1) * beta(time + 1, next);
        end
    end
    beta(time, :) = beta(time, :) / max(sum(beta(time, :)), realmin);
end
[informationLlr, codedLlr] = scfde.equalizers.ch4_probability_posteriors( ...
    alpha, beta, gamma, nextState, outputBits);
end
