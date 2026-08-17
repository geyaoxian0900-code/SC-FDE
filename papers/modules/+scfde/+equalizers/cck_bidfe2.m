function receiver = cck_bidfe2(channel, source, cfg)
%CCK_BIDFE2 CCK bidirectional DFE receiver, BiDFE-2 (book 5.3.2, Fig. 5-6).
%   The receiver follows the strict (5-52)~(5-54) signal flow recovered
%   from book/P133.png~P137.png: the forward DFE pass and the reversed
%   DFE pass use TWO INDEPENDENT feedback filters (never sharing state);
%   the second output (5-52) uses the forward hard decisions on the past
%   side and the reversed hard decisions (restored to the original time
%   order) on the future side; both filters use the composite
%   coefficients w_i = x_i / f_i = x_i ((5-53)/(5-54)).
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
limit = 128;
if isfield(cfg, "receiverCandidateLimit"), limit = cfg.receiverCandidateLimit; end
nv = cfg.noiseVariance;
if isempty(nv) || nv <= 0, nv = 10^(-cfg.snrDb / 10); end
[detected, soft] = scfde.equalizers.ch5_bidfe2_detect( ...
    channel.received, book, channel.impulse, nv, limit);
decisions = cck_indices_to_symbols(detected, source, book);
receiver = scfde.equalizers.pack_equalizer("CCK-BiDFE-2", "cck-bidfe2", ...
    decisions, zeros(size(decisions)), soft, ...
    struct("indices", detected, "forward", detected, ...
    "formulaStatus", "BLOCKED-SOURCE-REVIEW", ...
    "formulaMode", "book", ...
    "bookExperimentEquivalent", false, ...
    "effectiveParameters", struct("candidateLimit", limit), ...
    "formulaNote", "(5-52)~(5-54) BiDFE-2 signal flow from book/P133.png~P137.png (2026-08-17): two independent feedback filters, second output (5-52) with forward hard decisions on the past side and restored reversed hard decisions on the future side, w_i = x_i / f_i = x_i ((5-53)/(5-54)); certification promotion deferred to Task 9"));
end

function decisions = cck_indices_to_symbols(detected, source, book)
blockCount = numel(detected);
dataLength = numel(source.data);
decisions = zeros(1, dataLength);
for block = 1:min(blockCount, floor(dataLength / 8))
    decisions((block - 1) * 8 + (1:8)) = book(detected(block), :);
end
end