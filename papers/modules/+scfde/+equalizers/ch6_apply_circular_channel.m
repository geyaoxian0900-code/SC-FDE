function output = ch6_apply_circular_channel(book, channel)
lengthCode = size(book, 2);
response = ifft(fft(book, [], 2) .* fft(channel, lengthCode), [], 2);
scale = sqrt(mean(sum(abs(response).^2, 2)));
output = response / max(scale, eps);
end
