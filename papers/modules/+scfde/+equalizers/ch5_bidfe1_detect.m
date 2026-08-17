function [detected, soft] = ch5_bidfe1_detect(received, book, channel, ...
        noiseVariance, limit)
%CH5_BIDFE1_DETECT CCK BiDFE-1 detector (book 5.3.2, Fig. 5-5).
%   [DETECTED, SOFT] = CH5_BIDFE1_DETECT(RECEIVED, BOOK, CHANNEL, ...
%       NOISEVARIANCE, LIMIT)
%
% Signal flow recovered from book/P133.png~P137.png (2026-08-17):
%   1. forward tentative DFE (5-47): the soft residual of block k is the
%      observation minus the past-side spill of the FORWARD hard
%      decisions, and the current block decision never cancels itself
%      (the block's own response stays in its window);
%   2. block time reversal (5-48) rev[] = conj(fliplr) and the reverse
%      DFE (5-49) on the reversed stream: its restored soft residual
%      removes the FUTURE-side spill (the following original block's
%      response head, read backwards);
%   3. BiDFE-1 feedback coefficients (5-50)/(5-51): the forward and
%      reversed filters use the SAME composite coefficients w_i = x_i /
%      f_i = x_i, i = 1..L-1 (the CMF composite symmetry (5-42));
%   4. final bilateral cancellation (5-46):
%        softB1(k) = obs(k) - pastSpill(k) - futureSpill(k)
%                 = fwSoft(k) + revRestored(k) - obs(k)
%      with the forward branch on the past side and the reversed branch
%      (restored to the original time order) on the future side.
%   The output decisions are the nearest-codebook decisions on the
%   bilateral soft blocks; DETECTED and SOFT are in ORIGINAL block
%   order.
%
% The reversed branch windows do not cover the first `memory` frame
% chips; those positions take the forward branch alone (documented
% ENGINEERING head rule, same convention as ch5_tr_diversity_restore).
wordLength = 8;
lastTap = find(channel ~= 0, 1, "last");
if isempty(lastTap), lastTap = numel(channel); end
memory = lastTap - 1;
blockCount = ceil((numel(received) - numel(channel) + 1) / wordLength);
[fwIdx, ~, fwSoft] = scfde.equalizers.ch5_dfe_detect( ...
    received, book, channel, noiseVariance, limit);
[~, ~, bwSoft] = scfde.equalizers.ch5_backward_dfe_detect( ...
    received, book, channel, noiseVariance, limit);
revRestored = scfde.equalizers.ch5_tr_diversity_restore( ...
    bwSoft, numel(received), memory);
obsStream = received(1:blockCount * wordLength);
fwStream = reshape(fwSoft.', 1, []);
softStream = fwStream;
valid = ~isnan(revRestored(1:numel(fwStream)));
softStream(valid) = fwStream(valid) + revRestored(valid) - obsStream(valid);
soft = reshape(softStream, wordLength, []).';
detected = scfde.equalizers.ch5_nearest_book(soft, book);
end