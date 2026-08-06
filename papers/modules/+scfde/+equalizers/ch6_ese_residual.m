function [residual, variance] = ch6_ese_residual(symbol, target, posterior, context)
users = size(posterior, 3);
lengthCode = size(context.observation, 2);
residual = context.observation(symbol, :, target);
variance = context.noiseVariances(target) * ones(1, lengthCode);
for source = 1:users
    if source == target
        continue;
    end
    probability = reshape(posterior(symbol, :, source), 1, []);
    dictionary = context.dictionaries{target, source};
    meanWord = probability * dictionary;
    secondMoment = probability * abs(dictionary).^2;
    residual = residual - meanWord;
    variance = variance + max(0, secondMoment - abs(meanWord).^2);
end
end
