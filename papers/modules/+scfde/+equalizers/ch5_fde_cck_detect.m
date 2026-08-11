function [detected, history] = ch5_fde_cck_detect(received, book, channel, noiseVariance, iterations)
wordLength = size(book, 2);
% ceil keeps the last block even when the channel-tail overlap leaves
% fewer than memory samples at the end (floor gave blockCount 0 for a
% single 8-chip codeword: fft([]) -> empty .* product crash).
blockCount = ceil((numel(received) - numel(channel) + 1) / wordLength);
lengthFrame = blockCount * wordLength;
if numel(received) < lengthFrame
    received = [received, zeros(1, lengthFrame - numel(received))];
else
    received = received(1:lengthFrame);
end
H = fft([channel, zeros(1, lengthFrame - numel(channel))]);
Y = fft(received);
soft = zeros(1, lengthFrame);
history = zeros(iterations, blockCount);
residualEnergy = inf(1, iterations);
for iteration = 1:iterations
    reliability = min(0.98, wordLength * mean(abs(soft).^2));
    C = conj(H) ./ (noiseVariance + (1 - reliability) * abs(H).^2);
    C = C / mean(C .* H);
    B = C .* H - 1;
    estimate = ifft(C .* Y - B .* fft(soft));
    blocks = reshape(estimate, wordLength, []).';
    [detected, softWord] = scfde.equalizers.ch5_soft_book_detect(blocks, book, noiseVariance);
    candidateSoft = 0.65 * soft + 0.35 * reshape(softWord.', 1, []);
    reconstructed = filter(channel, 1, candidateSoft);
    residualEnergy(iteration) = mean(abs(received - reconstructed).^2);
    if iteration > 1 && residualEnergy(iteration) > residualEnergy(iteration - 1)
        residualEnergy(iteration) = residualEnergy(iteration - 1);
        history(iteration, :) = history(iteration - 1, :);
    else
        history(iteration, :) = detected;
        soft = candidateSoft;
    end
end
end
