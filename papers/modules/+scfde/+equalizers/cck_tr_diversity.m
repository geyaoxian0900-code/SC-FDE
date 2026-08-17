function receiver = cck_tr_diversity(channel, source, cfg)
%CCK_TR_DIVERSITY CCK time-reversal diversity receiver (book 5.5, (5-57)~(5-59)).
%   The forward BiDFE-2 branch and the time-reversed BiDFE-2 branch soft
%   outputs are restored to the same time order and merged with EQUAL
%   weight 1/2:
%       y(k) = ( ytilde(k) + ytilde_e(k) ) / 2          (5-57)
%   and each 8-chip block is decided on the merged soft chips with the
%   channel-model codebook decision (5-58).  Both branches are the exact
%   BiDFE-2 kernels (5-52)~(5-54) recovered from book/P133.png~P137.png
%   (2026-08-17); the frame head (no reversed window) falls back to the
%   forward branch alone (documented ENGINEERING rule).
%   (5-59) iterates the tentative decisions: the merged decisions of
%   iteration i seed the forward branch of iteration i+1 and their
%   reversal seeds the reversed branch; cfg.turboIterations controls the
%   count (default 1).
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
if isfield(cfg, "noiseVariance") && ~isempty(cfg.noiseVariance) && ...
        cfg.noiseVariance > 0
    nv = cfg.noiseVariance;
else
    nv = 10^(-cfg.snrDb / 10);
end
limit = 128;
if isfield(cfg, "receiverCandidateLimit"), limit = cfg.receiverCandidateLimit; end
iterations = 1;
if isfield(cfg, "turboIterations") && ~isempty(cfg.turboIterations)
    iterations = max(1, round(cfg.turboIterations));
end
% Effective channel memory: the last nonzero tap (trailing zeros do not
% create memory; the zero-state model slices the codeword response head).
lastTap = find(channel.impulse ~= 0, 1, "last");
if isempty(lastTap)
    lastTap = numel(channel.impulse);
end
memory = lastTap - 1;
priorForward = [];                 % (5-59): a_{i+1} = a_i
for iteration = 1:iterations
    % Forward branch: BiDFE-2 on the forward stream.
    [fwIdx, fwSoft] = scfde.equalizers.ch5_bidfe2_detect( ...
        channel.received, book, channel.impulse, nv, limit, priorForward);
    % Reversed branch: BiDFE-2 on the time-reversed stream, restored to
    % the same time order before the (5-57) merge.
    [revIdxRaw, revSoftRaw] = scfde.equalizers.ch5_bidfe2_detect( ...
        conj(fliplr(channel.received)), book, channel.impulse, nv, limit, ...
        fliplr(priorForward));
    revRestored = scfde.equalizers.ch5_tr_diversity_restore( ...
        revSoftRaw, numel(channel.received), memory);
    merged = scfde.equalizers.ch5_tr_diversity_combine(fwSoft, revRestored);
    mergedBlocks = reshape(merged, 8, []).';
    blockCount = size(mergedBlocks, 1);
    detected = zeros(1, blockCount);
    for block = 1:blockCount
        % (5-58) dec[y(k)]: full-codebook decision on the merged soft
        % block with the channel model.
        local = scfde.equalizers.ch5_candidate_scores( ...
            mergedBlocks(block, :), zeros(1, memory), book, ...
            channel.impulse, nv);
        [~, detected(block)] = max(local);
    end
    priorForward = detected;       % (5-59): tentative decisions advance
end
decisions = cck_indices_to_symbols(detected, source, book);
receiver = scfde.equalizers.pack_equalizer("CCK-TR-Diversity", ...
    "cck-tr-diversity", decisions, zeros(size(decisions)), merged, ...
    struct("indices", detected, "forward", fwIdx, ...
    "backward", fliplr(revIdxRaw), ...
    "branchForward", fwIdx, "branchBackward", fliplr(revIdxRaw), ...
    "formulaStatus", "ALG-EQUIV", ...
    "formulaMode", "book", ...
    "bookExperimentEquivalent", false, ...
    "sourcePages", "book/P133.png~book/P137.png", ...
    "sourceEquations", "(5-46)~(5-59)", ...
    "effectiveParameters", struct("candidateLimit", limit, ...
        "channelMemory", memory, "iterations", iterations), ...
    "combinerFormulaStatus", "BOOK-EXACT", ...
    "mergeEquation", "(5-57) y(k)=(ytilde(k)+ytilde_e(k))/2, equal weights 1/2", ...
    "restoreConvention", "rev[]=conj(fliplr); reverse branch restored to the same time order before merging", ...
    "branchSoftOutputStatus", "ALG-EQUIV", ...
    "branchSoftOutputNote", "branches are the exact BiDFE-2 kernels (5-52)~(5-54) from book/P133.png~P137.png; branch-level certification is ALG-EQUIV pending the per-symbol double review of (5-48)~(5-56)", ...
    "headRegionStatus", "ENGINEERING", ...
    "headRegionNote", "first 'memory' chips have no reversed-branch window: forward branch alone", ...
    "formulaNote", "weakest-link certification: (5-57) equal-weight 1/2 merge after same-time-order restoration is BOOK-EXACT and the branches are the strict BiDFE-2 kernels, but the branch-level per-symbol transcription and the (5-59) iteration are ALG-EQUIV, so the registered method as a whole is ALG-EQUIV", ...
    "decisionEquation", "(5-58) dec[y(k)] full-codebook decision with the channel model", ...
    "iterationEquation", "(5-59) a_{i+1}(k)=a_i(k), a_{e,i+1}(k)=rev[a_i](k)"));
end

function decisions = cck_indices_to_symbols(detected, source, book)
blockCount = numel(detected);
dataLength = numel(source.data);
decisions = zeros(1, dataLength);
for block = 1:min(blockCount, floor(dataLength / 8))
    decisions((block - 1) * 8 + (1:8)) = book(detected(block), :);
end
end