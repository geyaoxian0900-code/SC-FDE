function [detected, softWord] = ch5_soft_book_detect(observations, book, noiseVariance)
detected = zeros(1, size(observations, 1));
softWord = complex(zeros(size(observations)));
for index = 1:size(observations, 1)
    distance = sum(abs(book - observations(index, :)).^2, 2);
    [minimum, detected(index)] = min(distance);
    weights = exp(-(distance - minimum) / max(noiseVariance, 1e-8));
    weights = weights / sum(weights);
    softWord(index, :) = weights.' * book;
end
end
