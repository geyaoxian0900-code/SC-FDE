function prior = ch6_repeated_symbol_priors(likelihood, pair)
prior = zeros(size(likelihood));
informationSymbols = size(pair.information, 1);
users = size(pair.information, 2);
for user = 1:users
    for symbol = 1:informationSymbols
        second = pair.secondPosition(symbol, user);
        prior(symbol, :, user) = scfde.equalizers.ch6_normalize_log(likelihood(second, :, user));
        prior(second, :, user) = scfde.equalizers.ch6_normalize_log(likelihood(symbol, :, user));
    end
end
end
