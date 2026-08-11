function pair = ch6_repeated_symbol_indices(M, symbols, users)
informationSymbols = symbols / 2;
% Each information symbol must map to a DISTINCT codeword index, so
% the code indices are drawn without replacement (randperm); randi
% allowed duplicates (e.g. [4 4 1 4] for M=4), which made any
% index-to-information mapping non-unique.
pair.information = zeros(informationSymbols, users);
for user = 1:users
    pair.information(:, user) = randperm(M, informationSymbols).';
end
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
