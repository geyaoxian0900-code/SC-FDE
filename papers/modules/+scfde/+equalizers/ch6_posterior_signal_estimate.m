function soft = ch6_posterior_signal_estimate(posterior, dictionaries)
symbols = size(posterior, 1);
users = size(posterior, 3);
lengthCode = size(dictionaries{1}, 2);
soft = complex(zeros(users, symbols, lengthCode));
for user = 1:users
    for symbol = 1:symbols
        probability = reshape(posterior(symbol, :, user), 1, []);
        soft(user, symbol, :) = probability * dictionaries{user};
    end
end
end
