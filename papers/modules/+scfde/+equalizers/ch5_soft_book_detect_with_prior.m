function [detected, softWord, posteriorLlr] = ch5_soft_book_detect_with_prior( ...
        observations, book, bits, noiseVariance, priorWords)
blockCount = size(observations, 1);
bitCount = size(bits, 2);
detected = zeros(1, blockCount);
softWord = complex(zeros(size(observations)));
posteriorLlr = zeros(blockCount, bitCount);
for block = 1:blockCount
    distance = sum(abs(book - observations(block, :)).^2, 2);
    metric = -distance / max(noiseVariance, 1e-8) + ...
        0.5 * ((1 - 2 * bits) * priorWords(block, :).');
    [maximum, detected(block)] = max(metric);
    weights = exp(metric - maximum);
    weights = weights / sum(weights);
    softWord(block, :) = weights.' * book;
    for bit = 1:bitCount
        posteriorLlr(block, bit) = scfde.equalizers.ch5_log_sum_exp(metric(bits(:, bit) == 0)) - ...
            scfde.equalizers.ch5_log_sum_exp(metric(bits(:, bit) == 1));
    end
end
end
