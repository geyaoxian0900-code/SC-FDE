function [decisionHistory, mseHistory] = ch6_soft_sic_detect( ...
        received, dicts, noiseVariance, iterations, transmitted, logPriors)
symbols = size(received, 1);
users = numel(dicts);
M = size(dicts{1}, 1);
lengthCode = size(received, 2);
if isempty(logPriors)
    logPriors = zeros(symbols, M, users);
end
soft = complex(zeros(users, symbols, lengthCode));
decisionHistory = zeros(iterations, symbols, users);
mseHistory = zeros(iterations, 1);
for iteration = 1:iterations
    updated = soft;
    for symbol = 1:symbols
        for user = 1:users
            otherUsers = [1:user - 1, user + 1:users];
            interference = reshape(sum(soft(otherUsers, symbol, :), 1), 1, []);
            residual = received(symbol, :) - interference;
            interferenceVariance = noiseVariance * ones(1, lengthCode);
            for source = otherUsers
                sourceEnergy = mean(abs(dicts{source}).^2, 1);
                sourceMean = reshape(soft(source, symbol, :), 1, []);
                interferenceVariance = interferenceVariance + ...
                    max(0, sourceEnergy - abs(sourceMean).^2);
            end
            [decision, expected] = scfde.equalizers.ch6_soft_dictionary_detect(residual, dicts{user}, ...
                interferenceVariance, reshape(logPriors(symbol, :, user), 1, []));
            decisionHistory(iteration, symbol, user) = decision;
            updated(user, symbol, :) = expected;
        end
    end
    soft = 0.45 * soft + 0.55 * updated;
    mseHistory(iteration) = mean(abs(soft(:) - transmitted(:)).^2);
end
end
