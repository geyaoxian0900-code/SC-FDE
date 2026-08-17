function [detected, soft] = ch5_bidfe2_detect(received, book, channel, ...
        noiseVariance, limit, priorDecisions)
%CH5_BIDFE2_DETECT CCK BiDFE-2 detector (book 5.3.2, Fig. 5-6).
%   [DETECTED, SOFT] = CH5_BIDFE2_DETECT(RECEIVED, BOOK, CHANNEL, ...
%       NOISEVARIANCE, LIMIT, PRIORDECISIONS)
%
% Signal flow recovered from book/P133.png~P137.png (2026-08-17):
%   1. the forward DFE pass and the reversed DFE pass run with TWO
%      INDEPENDENT feedback filters - the forward filter is driven only
%      by the forward hard decisions and the reversed filter only by the
%      reversed hard decisions; state is NEVER shared between the two
%      directions;
%   2. the second output (5-52):
%        softB2(k) = obs(k) - pastSpill(k) - futureSpill(k)
%      where the past side is driven by the FORWARD hard decisions and
%      the future side by the REVERSED hard decisions restored to the
%      original time order (5-53)/(5-54): both filters use the composite
%      coefficients w_i = x_i / f_i = x_i, i = 1..L-1;
%   3. the current block decision never cancels itself (each block's own
%      response stays in its window), and the second-output decisions
%      are the nearest-codebook decisions on the bilateral soft blocks.
%
% PRIORDECISIONS (optional, (5-59)): tentative decisions of a previous
% iteration, in the SAME stream order as RECEIVED; they seed the initial
% state of the forward feedback filter (the past-side tentative
% decisions of the next iteration).  The reversed filter always runs a
% fresh reversed pass (rev[prior] enters through the reversed stream
% when the caller reverses the input, per (5-59)).  An empty/default
% prior keeps the unseeded first iteration unchanged.
%
% The method does NOT degenerate to a single forward DFE pass and does
% NOT average the two final hard codewords: the (5-52) soft output is a
% genuine bilateral cancellation with independent filters.
wordLength = 8;
lastTap = find(channel ~= 0, 1, "last");
if isempty(lastTap), lastTap = numel(channel); end
memory = lastTap - 1;
blockCount = ceil((numel(received) - numel(channel) + 1) / wordLength);
if nargin >= 6 && ~isempty(priorDecisions)
    prior = priorDecisions(:).';
    if numel(prior) ~= blockCount
        error("SCFDE:InvalidPriorDecisions", ...
            "priorDecisions must have exactly %d entries.", blockCount);
    end
    priorState = zeros(1, memory);
    for block = 1:numel(prior)
        priorState = scfde.equalizers.ch5_append_channel_state( ...
            priorState, book(prior(block), :), memory);
    end
    [fwIdx, ~, fwSoft] = scfde.equalizers.ch5_dfe_detect( ...
        received, book, channel, noiseVariance, limit, priorState);
else
    [fwIdx, ~, fwSoft] = scfde.equalizers.ch5_dfe_detect( ...
        received, book, channel, noiseVariance, limit);
end
[~, ~, bwSoft] = scfde.equalizers.ch5_backward_dfe_detect( ...
    received, book, channel, noiseVariance, limit);
revRestored = scfde.equalizers.ch5_tr_diversity_restore( ...
    bwSoft, numel(received), memory);
obsStream = received(1:blockCount * wordLength);
fwStream = reshape(fwSoft.', 1, []);
% Where the reversed window does not exist (frame head) the future-side
% spill is zero, so the second output reduces to the forward residual:
% revSafe = obsStream there keeps soft = obs - (obs-fw) - 0 = fwSoft.
revSafe = revRestored(1:blockCount * wordLength);
headMask = isnan(revSafe);
revSafe(headMask) = obsStream(headMask);
softStream = obsStream - (obsStream - fwStream) - (obsStream - revSafe);
soft = reshape(softStream, wordLength, []).';
detected = scfde.equalizers.ch5_nearest_book(soft, book);
end