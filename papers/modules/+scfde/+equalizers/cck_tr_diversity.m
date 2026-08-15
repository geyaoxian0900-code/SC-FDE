function receiver = cck_tr_diversity(channel, source, cfg)
%CCK_TR_DIVERSITY CCK time-reversal diversity receiver (book 5.5, (5-57)~(5-59)).
%   The forward DFE and the time-reversed DFE chip soft outputs are
%   restored to the same time order and merged with EQUAL weight:
%       y(k) = ( ytilde(k) + ytilde_e(k) ) / 2          (5-57)
%   and each 8-chip block is decided on the merged soft chips with the
%   channel-model codebook decision (5-58).  The branch temporary
%   decisions feed the next-block state recursion ((5-59) feedback
%   inside both DFE branches).
%   Replaces the previous multi-branch matched-filter + codebook
%   decision, which was NOT equation (5-57) and is forbidden by the
%   strict-formula spec (5.5).
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
if isfield(cfg, "noiseVariance") && ~isempty(cfg.noiseVariance) && ...
        cfg.noiseVariance > 0
    nv = cfg.noiseVariance;
else
    nv = 10^(-cfg.snrDb / 10);
end
limit = 128;
if isfield(cfg, "receiverCandidateLimit"), limit = cfg.receiverCandidateLimit; end
% Effective channel memory: the last nonzero tap (trailing zeros do not
% create memory; the zero-state model slices the codeword response head).
lastTap = find(channel.impulse ~= 0, 1, "last");
if isempty(lastTap)
    lastTap = numel(channel.impulse);
end
memory = lastTap - 1;
[forwardIdx, ~, forwardSoft] = scfde.equalizers.ch5_dfe_detect( ...
    channel.received, book, channel.impulse, nv, limit);
[backwardIdx, ~, backwardSoft] = scfde.equalizers.ch5_backward_dfe_detect( ...
    channel.received, book, channel.impulse, nv, limit);
reverseStream = scfde.equalizers.ch5_tr_diversity_restore( ...
    backwardSoft, numel(channel.received), memory);
merged = scfde.equalizers.ch5_tr_diversity_combine(forwardSoft, reverseStream);
mergedBlocks = reshape(merged, 8, []).';
blockCount = size(mergedBlocks, 1);
detected = zeros(1, blockCount);
for block = 1:blockCount
    % (5-58) dec[y(k)]: full-codebook decision on the merged soft block
    % with the channel model (first 8 taps of the candidate response;
    % reduces to the literal nearest-codeword dec[] under an identity
    % channel).  The merged chips already carry the spill-cancelled
    % residual, so the state term is zero here.
    local = scfde.equalizers.ch5_candidate_scores( ...
        mergedBlocks(block, :), zeros(1, memory), book, channel.impulse, nv);
    [~, detected(block)] = max(local);
end
decisions = cck_indices_to_symbols(detected, source, book);
receiver = scfde.equalizers.pack_equalizer("CCK-TR-Diversity", ...
    "cck-tr-diversity", decisions, zeros(size(decisions)), merged, ...
    struct("indices", detected, "forward", forwardIdx, "backward", backwardIdx, ...
    "formulaStatus", "BOOK-EXACT", ...
    "formulaMode", "book", ...
    "bookExperimentEquivalent", false, ...
    "effectiveParameters", struct("candidateLimit", limit, ...
        "channelMemory", memory), ...
    "combinerFormulaStatus", "BOOK-EXACT", ...
    "mergeEquation", "(5-57) y(k)=(ytilde(k)+ytilde_e(k))/2, equal weights 1/2", ...
    "restoreConvention", "rev[]=conj(fliplr); reverse branch restored to the same time order before merging", ...
    "branchSoftOutputStatus", "ALG-EQUIV", ...
    "branchSoftOutputNote", "chip-level DFE residual per (5-46)/(5-47) production model; exact branch-level chip equations pending (5-48~5-56) transcription", ...
    "headRegionStatus", "ENGINEERING", ...
    "headRegionNote", "first 'memory' chips have no reversed-branch window: forward branch alone", ...
    "decisionEquation", "(5-58) dec[y(k)] full-codebook decision with the channel model"));
end

function decisions = cck_indices_to_symbols(detected, source, book)
blockCount = numel(detected);
dataLength = numel(source.data);
decisions = zeros(1, dataLength);
for block = 1:min(blockCount, floor(dataLength / 8))
    decisions((block - 1) * 8 + (1:8)) = book(detected(block), :);
end
end
