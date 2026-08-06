function [dictionaries, channels] = ch6_idma_dictionaries(book, channel, users)
lengthCode = size(book, 2);
channels = scfde.equalizers.ch6_dictionary_channels(channel, users, lengthCode);
dictionaries = cell(1, users);
for user = 1:users
    permutation = randperm(lengthCode);
    dictionaries{user} = scfde.equalizers.ch6_apply_circular_channel(book(:, permutation), channels(user, :));
end
end
