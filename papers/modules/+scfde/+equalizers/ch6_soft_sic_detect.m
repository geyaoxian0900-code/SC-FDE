function [decisionHistory, mseHistory, userOrder] = ch6_soft_sic_detect( ...
        received, dicts, noiseVariance, iterations, transmitted, logPriors)
%CH6_SOFT_SIC_DETECT Soft serial interference cancellation (book 6.2.2,
% derived from (6-21)~(6-37); spec 6.2 - ID is at most ALG-EQUIV).
%
%   Users are ordered by RECEIVED POWER (mean dictionary energy,
%   descending): pi = userOrder.  For user pi(q) the residual is
%       r_res = r - sum_{p ~= q} H_{pi(p)} E[x_{pi(p)}],
%   where E[x] is the POSTERIOR soft mean of the user's own dictionary
%   (spec 6.2: cancellation values must come from posterior soft means
%   or already-decided users; NO fixed 0.45/0.55-style damping - the
%   old fixed damping is removed).  Within one pass users are processed
%   serially in pi order, so user pi(q) sees the FRESH estimates of
%   pi(1..q-1) and the previous-pass estimates of pi(q+1..M).
%
%   The chip-wise interference variance follows (6-25):
%       Var = sigma_w^2 + sum_{other} ( E|x|^2 - |E[x]|^2 )
%   with the posterior second moment E|x|^2 = p * |dict|.^2 (the old
%   mean-energy approximation mean(|dict|.^2, 1) is replaced by the
%   posterior-weighted moment, matching ch6_ese_residual).
%
%   decisionHistory: iterations x symbols x users (indexed by ORIGINAL
%   user id, so squeeze(history(end,:,1)) stays user 1 for the scenario
%   metric).  userOrder is the 1 x users processing order pi.
symbols = size(received, 1);
users = numel(dicts);
M = size(dicts{1}, 1);
lengthCode = size(received, 2);
if isempty(logPriors)
    logPriors = zeros(symbols, M, users);
end
if isscalar(noiseVariance)
    noiseVariance = repmat(noiseVariance, 1, lengthCode);
end
% User order by received power (descending mean dictionary energy).
energies = zeros(1, users);
for user = 1:users
    energies(user) = mean(abs(dicts{user}(:)).^2);
end
[~, userOrder] = sort(energies, "descend");
soft = complex(zeros(users, symbols, lengthCode));
posteriors = repmat(ones(symbols, M) / M, 1, 1, users);
decisionHistory = zeros(iterations, symbols, users);
mseHistory = zeros(iterations, 1);
for iteration = 1:iterations
    updated = soft;
    updatedPosteriors = posteriors;
    for symbol = 1:symbols
        for position = 1:users
            user = userOrder(position);
            interference = complex(zeros(1, lengthCode));
            variance = noiseVariance;
            for sourcePosition = 1:users
                source = userOrder(sourcePosition);
                if source == user
                    continue;
                end
                p = reshape(updatedPosteriors(symbol, :, source), 1, []);
                meanWord = p * dicts{source};
                secondMoment = p * abs(dicts{source}).^2;
                interference = interference + meanWord;
                variance = variance + max(0, secondMoment - abs(meanWord).^2);
            end
            residual = received(symbol, :) - interference;
            [decision, expected, ~, posterior] = ...
                scfde.equalizers.ch6_soft_dictionary_detect(residual, ...
                dicts{user}, variance, ...
                reshape(logPriors(symbol, :, user), 1, []));
            decisionHistory(iteration, symbol, user) = decision;
            updated(user, symbol, :) = expected;
            updatedPosteriors(symbol, :, user) = posterior;
        end
    end
    soft = updated;
    posteriors = updatedPosteriors;
    mseHistory(iteration) = mean(abs(soft(:) - transmitted(:)).^2);
end
end
