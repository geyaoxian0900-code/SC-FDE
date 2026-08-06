function dictionaries = ch6_conventional_dictionaries(book, channel, users)
lengthCode = size(book, 2);
channels = scfde.equalizers.ch6_dictionary_channels(channel, users, lengthCode);
dictionaries = cell(1, users);
for user = 1:users
    scramble = exp(1j * 2 * pi * (user - 1) * (0:lengthCode - 1) / lengthCode);
    userBook = circshift(book .* scramble, [0, mod(3 * user - 2, lengthCode)]);
    dictionaries{user} = scfde.equalizers.ch6_apply_circular_channel(userBook, channels(user, :));
end
end
