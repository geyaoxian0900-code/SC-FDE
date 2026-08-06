function context = ch6_ptr_context(received, dictionaries, userChannels, noiseVariance, enablePtr)
symbols = size(received, 1);
lengthCode = size(received, 2);
users = numel(dictionaries);
context.observation = complex(zeros(symbols, lengthCode, users));
context.dictionaries = cell(users, users);
context.noiseVariances = zeros(1, users);
context.equivalentChannels = complex(zeros(users, lengthCode));
receivedSpectrum = fft(received, [], 2);
for target = 1:users
    if enablePtr
        channelSpectrum = fft(userChannels(target, :), lengthCode);
        gain = max(sum(abs(userChannels(target, :)).^2), eps);
        matchedSpectrum = conj(channelSpectrum) / gain;
        context.observation(:, :, target) = ifft(receivedSpectrum .* ...
            repmat(matchedSpectrum, symbols, 1), [], 2);
        context.noiseVariances(target) = noiseVariance / gain;
        context.equivalentChannels(target, :) = ifft(abs(channelSpectrum).^2 / gain);
        for source = 1:users
            context.dictionaries{target, source} = ifft( ...
                fft(dictionaries{source}, [], 2) .* ...
                repmat(matchedSpectrum, size(dictionaries{source}, 1), 1), [], 2);
        end
    else
        context.observation(:, :, target) = received;
        context.noiseVariances(target) = noiseVariance;
        context.equivalentChannels(target, 1) = 1;
        for source = 1:users
            context.dictionaries{target, source} = dictionaries{source};
        end
    end
end
end
