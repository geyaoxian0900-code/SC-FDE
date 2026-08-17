function receiver = cck_bidfe(channel, source, cfg)
%CCK_BIDFE CCK bidirectional DFE receiver, BiDFE-1 (book 5.3.2, Fig. 5-5).
%   The receiver follows the strict (5-46)~(5-51) signal flow recovered
%   from book/P133.png~P137.png: the forward temporary decisions (5-47)
%   are taken BEFORE the block time reversal (5-48); the reversed DFE
%   (5-49) supplies the future-side estimates; the final bilateral
%   cancellation (5-46) removes the past-side ISI with the forward hard
%   decisions and the future-side ISI with the reversed estimates, and
%   the output is restored to the original time order.  Both feedback
%   filters use the composite coefficients w_i = x_i / f_i = x_i
%   ((5-50)/(5-51)); the current block decision never cancels itself.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
limit = 128;
if isfield(cfg, "receiverCandidateLimit"), limit = cfg.receiverCandidateLimit; end
nv = cfg.noiseVariance;
if isempty(nv) || nv <= 0, nv = 10^(-cfg.snrDb / 10); end
[detected, soft] = scfde.equalizers.ch5_bidfe1_detect( ...
    channel.received, book, channel.impulse, nv, limit);
decisions = cck_indices_to_symbols(detected, source, book);
receiver = scfde.equalizers.pack_equalizer("CCK-BiDFE-1", "cck-bidfe", ...
    decisions, zeros(size(decisions)), soft, ...
    struct("indices", detected, "forward", detected, ...
    "formulaStatus", "BLOCKED-SOURCE-REVIEW", ...
    "formulaMode", "book", ...
    "bookExperimentEquivalent", false, ...
    "effectiveParameters", struct("candidateLimit", limit), ...
    "formulaNote", "(5-46)~(5-51) BiDFE-1 signal flow from book/P133.png~P137.png (2026-08-17): forward tentative DFE (5-47) before BTR (5-48), reversed DFE (5-49), bilateral cancellation (5-46) with w_i = x_i / f_i = x_i ((5-50)/(5-51)), current block never cancels itself; certification promotion deferred to Task 9"));
end

function decisions = cck_indices_to_symbols(detected, source, book)
blockCount = numel(detected);
dataLength = numel(source.data);
decisions = zeros(1, dataLength);
for block = 1:min(blockCount, floor(dataLength / 8))
    decisions((block - 1) * 8 + (1:8)) = book(detected(block), :);
end
end