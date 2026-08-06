function channels = ch6_dictionary_channels(channel, users, lengthCode)
base = zeros(1, lengthCode);
base(1:min(numel(channel), lengthCode)) = channel(1:min(numel(channel), lengthCode));
channels = complex(zeros(users, lengthCode));
for user = 1:users
    delay = mod(2 * user - 2, max(1, floor(lengthCode / 4)));
    gain = 0.85 + 0.15 * cos(0.7 * user);
    phase = exp(1j * 0.35 * (user - 1));
    channels(user, :) = gain * phase * circshift(base, delay);
    channels(user, :) = channels(user, :) / max(norm(channels(user, :)), eps);
end
end
