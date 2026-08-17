function [detected, softWord, posteriorLlr] = ch5_soft_book_detect_with_prior( ...
        observations, book, bits, noiseVariance, priorWords)
%CH5_SOFT_BOOK_DETECT_WITH_PRIOR MAP-CCK-TE posterior LLR detector
% (book (5-64)~(5-69), recovered from book/P138.png~P140.png, 2026-08-17).
%   The posterior LLR of bit i is the log-sum-exp over the codewords
%   whose bit i is 0 minus the log-sum-exp over the codewords whose bit
%   i is 1, where each codeword metric carries the AWGN likelihood and
%   the product of the bit priors built from the prior LLRs:
%       metric(c) = -||obs - c||^2/sigma^2 + sum_j ln P(b_j(c)),
%       L_post(i) = logsumexp_{b_i=0} metric - logsumexp_{b_i=1} metric
%   with P(b=0)/P(b=1) = exp(L_a).  The prior term is written as
%   0.5*(1-2b)*L_a, which equals ln P(b) up to the per-bit constant
%   -ln(2cosh(L_a/2)) that cancels in the LLR difference.
%   (5-69) splits the posterior into the EXTRINSIC part (likelihood and
%   every OTHER bit's prior) plus the bit's OWN prior LLR:
%       L_post(i) = L_ext(i) + L_a(i);
%   the caller must feed ONLY the extrinsic back (L_ext = L_post - L_a);
%   feeding the posterior back double-counts the prior.
blockCount = size(observations, 1);
bitCount = size(bits, 2);
detected = zeros(1, blockCount);
softWord = complex(zeros(size(observations)));
posteriorLlr = zeros(blockCount, bitCount);
for block = 1:blockCount
    distance = sum(abs(book - observations(block, :)).^2, 2);
    metric = -distance / max(noiseVariance, 1e-8) + ...
        0.5 * ((1 - 2 * bits) * priorWords(block, :).');
    [maximum, detected(block)] = max(metric);
    weights = exp(metric - maximum);
    weights = weights / sum(weights);
    softWord(block, :) = weights.' * book;
    for bit = 1:bitCount
        posteriorLlr(block, bit) = scfde.equalizers.ch5_log_sum_exp(metric(bits(:, bit) == 0)) - ...
            scfde.equalizers.ch5_log_sum_exp(metric(bits(:, bit) == 1));
    end
end
end
