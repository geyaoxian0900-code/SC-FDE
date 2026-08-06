function [decision, expected] = ch6_matched_filter_detect(received, dicts)
symbols = size(received, 1);
users = numel(dicts);
decision = zeros(symbols, users);
expected = complex(zeros(users, symbols, size(received, 2)));
for symbol = 1:symbols
    for user = 1:users
        [decision(symbol, user), expected(user, symbol, :)] = ...
            scfde.equalizers.ch6_hard_dictionary_detect(received(symbol, :), dicts{user});
    end
end
end
