function [innerDecision, outerDecision, innerMse, outerMse, directDecision, trace] = ...
        csk_idma_detect(received, dicts, userChannels, noiseVariance, pair, ...
        innerIterations, outerIterations, transmitted, enablePtr, damping)
% Equation (6-21) is evaluated in the PTR domain.  The ESE computes the
% codeword mean and chip-wise variance in (6-22)-(6-31), then transfers the
% resulting symbol likelihood to the interleaved repetition decoder.
symbols = size(received, 1);
users = numel(dicts);
M = size(dicts{1}, 1);
lengthCode = size(received, 2);
context = scfde.equalizers.ch6_ptr_context(received, dicts, userChannels, noiseVariance, enablePtr);
posterior = ones(symbols, M, users) / M;
logPrior = zeros(symbols, M, users);
innerDecision = zeros(innerIterations, size(pair.information, 1), users);
outerDecision = zeros(outerIterations, size(pair.information, 1), users);
innerMse = zeros(innerIterations, 1);
outerMse = zeros(outerIterations, 1);
directDecision = zeros(symbols, users);
lastVariance = noiseVariance * ones(1, lengthCode);
for outer = 1:outerIterations
    likelihood = zeros(symbols, M, users);
    for inner = 1:innerIterations
        updatedPosterior = posterior;
        for symbol = 1:symbols
            for user = 1:users
                [residual, interferenceVariance] = scfde.equalizers.ch6_ese_residual(symbol, user, ...
                    posterior, context);
                [directDecision(symbol, user), ~, metric, probability] = ...
                    scfde.equalizers.ch6_soft_dictionary_detect(residual, context.dictionaries{user, user}, ...
                    interferenceVariance, reshape(logPrior(symbol, :, user), 1, []));
                likelihood(symbol, :, user) = metric;
                updatedPosterior(symbol, :, user) = probability;
                if symbol == 1 && user == 1
                    lastVariance = interferenceVariance;
                end
            end
        end
        posterior = (1 - damping) * posterior + damping * updatedPosterior;
        decoded = scfde.equalizers.ch6_repeated_symbol_decode(likelihood, pair);
        if outer == 1
            innerDecision(inner, :, :) = decoded;
            soft = scfde.equalizers.ch6_posterior_signal_estimate(posterior, dicts);
            innerMse(inner) = mean(abs(soft(:) - transmitted(:)).^2);
        end
    end
    decoded = scfde.equalizers.ch6_repeated_symbol_decode(likelihood, pair);
    outerDecision(outer, :, :) = decoded;
    soft = scfde.equalizers.ch6_posterior_signal_estimate(posterior, dicts);
    outerMse(outer) = mean(abs(soft(:) - transmitted(:)).^2);
    logPrior = scfde.equalizers.ch6_repeated_symbol_priors(likelihood, pair);
end
trace.ptrEnabled = enablePtr;
trace.ptrReceivedUser1 = context.observation(:, :, 1);
trace.ptrEquivalentChannelUser1 = context.equivalentChannels(1, :);
trace.effectiveNoiseVariance = context.noiseVariances;
trace.eseVarianceUser1Symbol1 = lastVariance;
trace.finalPosteriorUser1 = squeeze(posterior(:, :, 1));
end