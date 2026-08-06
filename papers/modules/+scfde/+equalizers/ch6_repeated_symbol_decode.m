function decoded = ch6_repeated_symbol_decode(likelihood, pair)
informationSymbols = size(pair.information, 1);
users = size(pair.information, 2);
decoded = zeros(informationSymbols, users);
for user = 1:users
    for symbol = 1:informationSymbols
        second = pair.secondPosition(symbol, user);
        metric = likelihood(symbol, :, user) + likelihood(second, :, user);
        [~, decoded(symbol, user)] = max(metric);
    end
end
end
