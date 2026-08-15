function [detected, history] = ch5_fde_cck_detect(received, book, channel, noiseVariance, iterations)
%CH5_FDE_CCK_DETECT CCK frequency-domain IBDFE detection (spec 5.6, (5-80)).
%   X_hat^(i) = C^(i) .* Y - B^(i) .* X_bar^(i-1),  C/B per (5-75)~(5-80)
%   with the production MMSE coefficient form (row (5-80) ALG-EQUIV).
%   The soft codebook estimate follows (5-81)/(5-82): the posterior
%   mean x_bar = sum_q a_q P(a_q | x_hat) with the exponential
%   likelihood (ch5_soft_book_detect).  The previous FIXED 0.65/0.35
%   soft mixing and the residual-energy rollback are removed (spec 5.6:
%   fixed reliability mixing and performance rollback are NOT part of
%   the book equations).
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
    % Reliability measure for the coefficient variance ((5-83)~(5-96)
    % derivation region is transcription-pending; this estimate is
    % ALG-EQUIV and recorded).
    reliability = min(0.98, wordLength * mean(abs(soft).^2));
    C = conj(H) ./ (noiseVariance + (1 - reliability) * abs(H).^2);
    C = C / mean(C .* H);
    B = C .* H - 1;
    estimate = ifft(C .* Y - B .* fft(soft));
    blocks = reshape(estimate, wordLength, []).';
    [detected, softWord] = scfde.equalizers.ch5_soft_book_detect(blocks, book, noiseVariance);
    % (5-81)/(5-82): the feedback is the posterior mean, undamped.
    soft = reshape(softWord.', 1, []);
    history(iteration, :) = detected;
    reconstructed = filter(channel, 1, soft);
    residualEnergy(iteration) = mean(abs(received - reconstructed).^2);
end
end
