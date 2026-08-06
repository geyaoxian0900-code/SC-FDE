function [informationHistory, residualEnergy] = ch5_fde_cck_turbo_detect( ...
        frame, book, bits, channel, iterations, damping)
wordLength = size(book, 2);
bitCount = size(bits, 2);
blockCount = numel(frame.indices);
lengthFrame = blockCount * wordLength;
received = frame.received(1:lengthFrame);
H = fft([channel, zeros(1, lengthFrame - numel(channel))]);
Y = fft(received);
soft = zeros(1, lengthFrame);
prior = zeros(1, blockCount * bitCount);
informationHistory = false(iterations, numel(frame.informationBits));
residualEnergy = zeros(1, iterations);
for iteration = 1:iterations
    reliability = min(0.98, wordLength * mean(abs(soft).^2));
    C = conj(H) ./ (frame.noiseVariance + (1 - reliability) * abs(H).^2);
    C = C / mean(C .* H);
    B = C .* H - 1;
    estimate = ifft(C .* Y - B .* fft(soft));
    blocks = reshape(estimate, wordLength, []).';
    priorWords = reshape(prior, bitCount, []).';
    [~, softWord, posteriorLlr] = scfde.equalizers.ch5_soft_book_detect_with_prior( ...
        blocks, book, bits, frame.noiseVariance, priorWords);
    channelExtrinsic = reshape(posteriorLlr.', 1, []) - prior;
    informationLlr = channelExtrinsic(frame.firstCopy) + ...
        channelExtrinsic(frame.pairedPosition(frame.firstCopy));
    informationHistory(iteration, :) = informationLlr < 0;
    prior = damping * channelExtrinsic(frame.pairedPosition);
    candidateSoft = reshape(softWord.', 1, []);
    soft = 0.65 * soft + 0.35 * candidateSoft;
    reconstructed = filter(channel, 1, soft);
    residualEnergy(iteration) = mean(abs(received - reconstructed).^2);
end
end
