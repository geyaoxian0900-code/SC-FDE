function pair = ch6_repeated_symbol_indices(M, symbols, users)
informationSymbols = symbols / 2;
pair.information = randi(M, informationSymbols, users);
pair.indices = zeros(symbols, users);
pair.secondPosition = zeros(informationSymbols, users);
pair.indices(1:informationSymbols, :) = pair.information;
for user = 1:users
    interleaver = randperm(informationSymbols);
    pair.indices(informationSymbols + 1:end, user) = ...
        pair.information(interleaver, user);
    inverseInterleaver = zeros(1, informationSymbols);
    inverseInterleaver(interleaver) = 1:informationSymbols;
    pair.secondPosition(:, user) = informationSymbols + inverseInterleaver(:);
end
end
