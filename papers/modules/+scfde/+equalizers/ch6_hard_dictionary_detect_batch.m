function [decision, distance] = ch6_hard_dictionary_detect_batch(received, book)
decision = zeros(size(received, 1), 1);
distance = zeros(size(received, 1), 1);
for symbol = 1:size(received, 1)
    values = sum(abs(book - received(symbol, :)).^2, 2);
    [distance(symbol), decision(symbol)] = min(values);
end
end
