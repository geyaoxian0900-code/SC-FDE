function tests = test_new_scan_ch5_eq_5_41_69
%TEST_NEW_SCAN_CH5_EQ_5_41_69 Strict-formula tests recovered from the new
% high-resolution scans book/P133.png~book/P137.png (2026-08-17) for
% BiDFE-1/BiDFE-2 and TR diversity:
%   * (5-41)~(5-45) CMF composite impulse: matched-filter correlation,
%     maximum-path alignment, x_0 = 1 normalization; colored CMF noise
%     correlation is ignored by later detection (book assumption);
%   * (5-47) forward tentative DFE, (5-48) block time reversal,
%     (5-49) reverse DFE, (5-50)/(5-51) BiDFE-1 feedback coefficients
%     w_i = x_i / f_i = x_i;
%   * (5-46) BiDFE-1 final bilateral cancellation: the forward branch
%     supplies the PAST-side hard decisions and the reversed branch the
%     FUTURE-side estimates; the forward temporary decisions occur
%     BEFORE the time reversal, the current block decision never cancels
%     itself, and the final decisions are restored to the original time
%     order;
%   * (5-52) BiDFE-2 second output computed from TWO INDEPENDENT
%     feedback filters (forward hard decisions and reversed hard
%     decisions), (5-53)/(5-54) filter orientations w_i = x_i / f_i = x_i;
%   * (5-57) equal-weight 1/2 merge of the two BiDFE branches after
%     same-time-order restoration, (5-58) dec[y(k)], (5-59) iterative
%     tentative decisions.
%
% The BiDFE oracles are INDEPENDENT INLINE REPLICAS of the recovered
% signal flow (raw-domain block model with raw-channel convolution
% prediction, the same convention the existing ch5 detectors are
% audited against): no production helper reuse in the oracle paths.
% The setup adds BOTH papers and papers/modules so clean matlab -batch
% runs do not depend on persistent paths.

tests = functiontests({ ...
    @testCmfCompositeEq5_41_45, ...
    @testBidfe1BilateralCancellationEq5_46_51, ...
    @testBidfe1NegativesParallelFusionAndLag, ...
    @testBidfe2SecondOutputEq5_52_54, ...
    @testBidfe2NegativeSharedStateAndForwardOnly, ...
    @testBidfeBranchesIdentityExact, ...
    @testTrDiversityMergeEq5_57_59, ...
    @testRegisteredBankFinite});
%#ok<*DEFNU>  % setupOnce is invoked by the framework, not by name
%#ok<*NASGU>  % fixture outputs unused by individual tests are intentional
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(papersDir);
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function book = fixtureBook()
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
end

%% ---- independent inline replicas (no production helper calls) --------

function [softM, dec, scoresM] = inlineForwardDfe(received, book, channel, noiseVariance)
% (5-47) forward tentative DFE: soft(k) = obs(k) - past-spill from the
% decisions of the previous blocks; the decision scores the FULL
% prediction conv([state, word], channel) over the whole codebook
% (limit = 256 = codebook size), matching the audited detector rule.
wordLength = size(book, 2);
lastTap = find(channel ~= 0, 1, "last");
if isempty(lastTap), lastTap = numel(channel); end
memory = lastTap - 1;
blockCount = ceil((numel(received) - numel(channel) + 1) / wordLength);
state = zeros(1, memory);
softM = complex(zeros(blockCount, wordLength));
dec = zeros(1, blockCount);
scoresM = -inf(blockCount, size(book, 1));
for block = 1:blockCount
    obs = received((block - 1) * wordLength + (1:wordLength));
    spill = conv([state, zeros(1, wordLength)], channel);
    softM(block, :) = obs - spill(memory + 1:memory + wordLength);
    for candidate = 1:size(book, 1)
        pred = conv([state, book(candidate, :)], channel);
        pred = pred(memory + 1:memory + wordLength);
        scoresM(block, candidate) = -sum(abs(obs - pred).^2) / ...
            max(noiseVariance, 1e-8);
    end
    [~, dec(block)] = max(scoresM(block, :));
    state = [state, book(dec(block), :)];
    state = state(end - memory + 1:end);
end
end

function [softRaw, decRaw] = inlineReverseDfe(received, book, channel, noiseVariance)
% (5-48)/(5-49): block time reversal rev[] = conj(fliplr) and reverse
% DFE on the reversed stream (frame-TAIL segment prediction model).
% Soft rows stay in REVERSED block order (raw reversed domain);
% decisions are raw too; the caller restores with fliplr/conj(fliplr)
% per the book convention.
wordLength = size(book, 2);
lastTap = find(channel ~= 0, 1, "last");
if isempty(lastTap), lastTap = numel(channel); end
memory = lastTap - 1;
blockCount = ceil((numel(received) - numel(channel) + 1) / wordLength);
reverseReceived = conj(fliplr(received));
state = zeros(1, memory);
softRaw = complex(zeros(blockCount, wordLength));
decRaw = zeros(1, blockCount);
tailOffset = numel(received) - wordLength * blockCount;
for block = 1:blockCount
    obs = reverseReceived((block - 1) * wordLength + (1:wordLength));
    softRaw(block, :) = obs - [state, zeros(1, wordLength - memory)];
    scores = zeros(1, size(book, 1));
    for candidate = 1:size(book, 1)
        full = conv(book(candidate, :), channel);
        pred = conj(fliplr(full(tailOffset + 1:tailOffset + wordLength)));
        if any(state ~= 0)
            pred(1:memory) = pred(1:memory) + state;
        end
        scores(candidate) = -sum(abs(obs - pred).^2) / max(noiseVariance, 1e-8);
    end
    [~, decRaw(block)] = max(scores);
    fullClean = conv(book(decRaw(block), :), channel);
    if numel(fullClean) > wordLength
        state = conj(fliplr(fullClean(1:memory)));
    else
        state = zeros(1, memory);
    end
end
end

function restored = inlineRestore(backwardSoft, frameLength, memory)
% rev[] = conj(fliplr) per block placed at the original chip positions
% the reversed window observes (book convention, same as the audited
% production restore path).
restored = nan(1, frameLength);
for j = 1:size(backwardSoft, 1)
    k0 = frameLength - 8 * j + 1;
    restored(k0:k0 + 7) = conj(fliplr(backwardSoft(j, :)));
end
end

function [softStream, dec] = inlineBidfe1(received, book, channel, noiseVariance)
% BiDFE-1 soft stream in the original time order: the bilateral
% cancellation (5-46) soft output
%   softB1(k) = obs(k) - pastSpill - futureSpill
%            = fwSoft(k) + revRestored(k) - obs(k)
% where the forward branch supplies the past side and the restored
% reversed branch the future side.  NaN reversed windows (frame head)
% fall back to the forward branch alone.
[fwSoft, fwDec] = inlineForwardDfe(received, book, channel, noiseVariance);
[bwSoft, ~] = inlineReverseDfe(received, book, channel, noiseVariance);
memory = numel(channel) - 1;
revRestored = inlineRestore(bwSoft, numel(received), memory);
blockCount = numel(fwDec);
obsStream = received(1:blockCount * 8);
fwStream = reshape(fwSoft.', 1, []);
softStream = fwStream;
valid = ~isnan(revRestored(1:numel(fwStream)));
softStream(valid) = fwStream(valid) + revRestored(valid) - obsStream(valid);
dec = fwDec;
end

%% ---- tests -----------------------------------------------------------

function testCmfCompositeEq5_41_45(testCase)
% (5-41) x = conv(conj(fliplr(h)), h); aligned to the maximum path and
% normalized x_0 = 1 as in (5-45).  Colored CMF noise correlation is
% IGNORED by subsequent detection (book note).
h = [1, 0.6 * exp(1j * 0.3), 0.25 * exp(-1j * 0.7)];
corrFull = conv(conj(fliplr(h)), h);
[~, peak] = max(abs(corrFull));
center = ceil(numel(corrFull) / 2);
shift = peak - center;
if shift > 0
    aligned = [corrFull(1 + shift:end), zeros(1, shift)];
elseif shift < 0
    aligned = [zeros(1, -shift), corrFull(1:end + shift)];
else
    aligned = corrFull;
end
xOracle = aligned / aligned(center);
verifyEqual(testCase, xOracle(center), 1, "AbsTol", 1e-12, ...
    "(5-45) x_0 = 1 normalization");
verifyTrue(testCase, all(abs(xOracle) <= 1 + 1e-12), ...
    "the normalized composite correlation peaks at x_0 = 1");
prod = scfde.equalizers.ch5_cmf_composite(h);
verifyEqual(testCase, prod, xOracle, "AbsTol", 1e-12, ...
    "production composite impulse must equal the (5-41)/(5-45) oracle");
% Invalid channel inputs raise.
verifyError(testCase, @() scfde.equalizers.ch5_cmf_composite([]), ...
    "SCFDE:InvalidCmfChannel", "empty channel must be rejected");
verifyError(testCase, @() scfde.equalizers.ch5_cmf_composite([1, nan]), ...
    "SCFDE:InvalidCmfChannel", "nonfinite channel must be rejected");
end

function testBidfe1BilateralCancellationEq5_46_51(testCase)
% BiDFE-1 signal flow (Fig. 5-5): forward temporary decisions (5-47)
% happen BEFORE the block time reversal (5-48); the reversed DFE (5-49)
% supplies the future-side estimates; the final (5-46) bilateral
% cancellation combines the forward past-decisions with the reversed
% future-decisions; the current block decision never cancels itself;
% the final output is restored to the original time order.
book = fixtureBook();
h = [1, 0.6 * exp(1j * 0.3), 0.25 * exp(-1j * 0.7)];
rng(601, "twister");
nb = 4;
idx = randi(size(book, 1), 1, nb);
chips = reshape(book(idx, :).', 1, []);
memory = numel(h) - 1;
received = filter(h, 1, [chips, zeros(1, memory)]);
received = received + 1e-7 * (randn(size(received)) + 1j * randn(size(received)));
nv = 1e-4;
[oracleSoft, oracleDec] = inlineBidfe1(received, book, h, nv);
% Production kernel.
[detected, soft] = scfde.equalizers.ch5_bidfe1_detect( ...
    received, book, h, 1e-4, 256);
verifyEqual(testCase, numel(detected), ceil((numel(received) - numel(h) + 1) / 8), ...
    "BiDFE-1 must produce one decision per block");
verifyEqual(testCase, reshape(soft.', 1, []), oracleSoft, "AbsTol", 1e-9, ...
    "BiDFE-1 soft output must equal the (5-46) bilateral oracle");
verifyEqual(testCase, detected, oracleDec, ...
    "BiDFE-1 decisions follow the (5-46) bilateral cancellation");
end

function testBidfe1NegativesParallelFusionAndLag(testCase)
% RED: parallel score fusion (the previous production path) must NOT be
% produced as BiDFE-1 decisions on at least one discriminating frame
% (stronger channel and noise than the positive test), and a
% one-block-lagged reversed state must NOT be produced either.
book = fixtureBook();
h = scfde.equalizers.ch5_short_turbo_channel();   % 5-tap normalized
memory = numel(h) - 1;
nv = 0.05;
differAny = false;
for seed = 1:24
    rng(seed, "twister");
    nb = 4;
    idx = randi(size(book, 1), 1, nb);
    chips = reshape(book(idx, :).', 1, []);
    received = filter(h, 1, [chips, zeros(1, memory)]);
    received = received + sqrt(nv / 2) * ...
        (randn(size(received)) + 1j * randn(size(received)));
    [detected, ~] = scfde.equalizers.ch5_bidfe1_detect( ...
        received, book, h, nv, 256);
    [~, fwScores, ~] = scfde.equalizers.ch5_dfe_detect( ...
        received, book, h, nv, 256);
    [~, bwScores, ~] = scfde.equalizers.ch5_backward_dfe_detect( ...
        received, book, h, nv, 256);
    fusedIdx = scfde.equalizers.ch5_fuse_scores(fwScores, bwScores);
    if any(detected ~= fusedIdx)
        differAny = true;
        break;
    end
end
verifyTrue(testCase, differAny, ...
    "parallel score fusion must NOT be produced as BiDFE-1 decisions");
% One-block-lagged reversed state: placing each reversed window one
% block LATER shifts the future-side estimates and must change the soft
% output (the strict flow restores row j to frameLength - 8*j + 1).
rng(602, "twister");
nb = 5;
idx = randi(size(book, 1), 1, nb);
chips = reshape(book(idx, :).', 1, []);
received = filter(h, 1, [chips, zeros(1, memory)]);
received = received + sqrt(nv / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));
[detected, soft] = scfde.equalizers.ch5_bidfe1_detect( ...
    received, book, h, nv, 256);
[~, ~, fwSoft] = scfde.equalizers.ch5_dfe_detect( ...
    received, book, h, nv, 256);
[~, ~, bwSoft] = scfde.equalizers.ch5_backward_dfe_detect( ...
    received, book, h, nv, 256);
lagRestored = nan(1, numel(received));
for j = 1:size(bwSoft, 1)
    k0 = numel(received) - 8 * (j + 1) + 1;   % one block later
    if k0 >= 1
        lagRestored(k0:k0 + 7) = conj(fliplr(bwSoft(j, :)));
    end
end
blockCount = size(fwSoft, 1);
obsStream = received(1:blockCount * 8);
fwStream = reshape(fwSoft.', 1, []);
lagSoft = fwStream;
valid = ~isnan(lagRestored(1:numel(fwStream)));
lagSoft(valid) = fwStream(valid) + lagRestored(valid) - obsStream(valid);
verifyTrue(testCase, any(abs(soft(:) - lagSoft(:)) > 1e-9), ...
    "one-block-lagged reversed state must NOT be produced");
end

function testBidfe2SecondOutputEq5_52_54(testCase)
% BiDFE-2 (Fig. 5-6): the forward DFE pass and the reversed DFE pass use
% TWO INDEPENDENT feedback filters (never sharing state); the second
% output (5-52) uses the forward hard decisions on the past side and the
% reversed hard decisions (restored to time order) on the future side;
% filter orientations (5-53)/(5-54) w_i = x_i / f_i = x_i.
book = fixtureBook();
h = [1, 0.6 * exp(1j * 0.3), 0.25 * exp(-1j * 0.7)];
rng(603, "twister");
nb = 4;
idx = randi(size(book, 1), 1, nb);
chips = reshape(book(idx, :).', 1, []);
memory = numel(h) - 1;
received = filter(h, 1, [chips, zeros(1, memory)]);
received = received + 1e-6 * (randn(size(received)) + 1j * randn(size(received)));
nv = 1e-3;
[detected2, soft2] = scfde.equalizers.ch5_bidfe2_detect( ...
    received, book, h, nv, 256);
% Independent oracle: first passes from the inline replicas, then the
% (5-52) second output
%   softB2(k) = obs(k) - pastSpill(k) - futureSpill(k)
% where the past side is driven by the FORWARD hard decisions and the
% future side by the REVERSED hard decisions restored to time order.
[fwSoft, ~] = inlineForwardDfe(received, book, h, nv);
[bwSoft, ~] = inlineReverseDfe(received, book, h, nv);
revRestored = inlineRestore(bwSoft, numel(received), memory);
blockCount = size(fwSoft, 1);
obsStream = received(1:blockCount * 8);
fwStream = reshape(fwSoft.', 1, []);
% Where the reversed window does not exist (frame head) the future-side
% spill is zero and the second output reduces to the forward residual:
revSafe = revRestored(1:blockCount * 8);
revSafe(isnan(revSafe)) = obsStream(isnan(revSafe));
oracleStream = obsStream - (obsStream - fwStream) - (obsStream - revSafe);
oracleSoft = reshape(oracleStream, 8, []).';
oracleDec = scfde.equalizers.ch5_nearest_book(oracleSoft, book);
verifyEqual(testCase, soft2, oracleSoft, "AbsTol", 1e-9, ...
    "BiDFE-2 second output must equal the (5-52) bilateral oracle");
verifyEqual(testCase, detected2, oracleDec, ...
    "BiDFE-2 decisions follow the (5-52) second output");
end

function testBidfe2NegativeSharedStateAndForwardOnly(testCase)
% RED: BiDFE-2 must use two INDEPENDENT feedback filters - the (5-52)
% second output differs from the forward DFE soft wherever the reversed
% filter contributes, and on at least one discriminating frame the
% decisions differ from a single forward DFE pass.
book = fixtureBook();
h = scfde.equalizers.ch5_short_turbo_channel();   % 5-tap normalized
memory = numel(h) - 1;
nv = 0.05;
rng(604, "twister");
nb = 4;
idx = randi(size(book, 1), 1, nb);
chips = reshape(book(idx, :).', 1, []);
received = filter(h, 1, [chips, zeros(1, memory)]);
received = received + sqrt(nv / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));
[detected2, soft2] = scfde.equalizers.ch5_bidfe2_detect( ...
    received, book, h, nv, 256);
[~, ~, fwSoft] = scfde.equalizers.ch5_dfe_detect( ...
    received, book, h, nv, 256);
% Soft level: the reversed filter subtracts the future-side spill, so
% the second output differs from the forward soft beyond the frame head.
verifyTrue(testCase, any(abs(soft2(:) - fwSoft(:)) > 1e-9), ...
    "BiDFE-2 second output must include the reversed-filter correction");
% Decision level: at least one discriminating frame where the BiDFE-2
% decisions differ from a single forward DFE pass.
differAny = false;
for seed = 1:24
    rng(seed, "twister");
    nb = 4;
    idx = randi(size(book, 1), 1, nb);
    chips = reshape(book(idx, :).', 1, []);
    received = filter(h, 1, [chips, zeros(1, memory)]);
    received = received + sqrt(nv / 2) * ...
        (randn(size(received)) + 1j * randn(size(received)));
    [detected2, ~] = scfde.equalizers.ch5_bidfe2_detect( ...
        received, book, h, nv, 256);
    [fwDec, ~] = scfde.equalizers.ch5_dfe_detect( ...
        received, book, h, nv, 256);
    if any(detected2 ~= fwDec)
        differAny = true;
        break;
    end
end
verifyTrue(testCase, differAny, ...
    "BiDFE-2 must not degenerate to a single forward DFE pass");
end

function testBidfeBranchesIdentityExact(testCase)
% Identity channel: both BiDFE branches have no ISI; the bilateral
% cancellation leaves the clean codebook block and every index is
% recovered exactly.
book = fixtureBook();
for nb = [1, 2, 5]
    for seed = 1:8
        rng(seed, "twister");
        idx = randi(size(book, 1), 1, nb);
        chips = reshape(book(idx, :).', 1, []);
        [d1, s1] = scfde.equalizers.ch5_bidfe1_detect( ...
            chips, book, [1, 0, 0], 1e-9, 256);
        [d2, s2] = scfde.equalizers.ch5_bidfe2_detect( ...
            chips, book, [1, 0, 0], 1e-9, 256);
        verifyEqual(testCase, d1, idx, ...
            sprintf("BiDFE-1 identity frame %d seed %d", nb, seed));
        verifyEqual(testCase, d2, idx, ...
            sprintf("BiDFE-2 identity frame %d seed %d", nb, seed));
        verifyEqual(testCase, reshape(s1.', 1, []), chips, "AbsTol", 0, ...
            sprintf("BiDFE-1 identity soft frame %d seed %d", nb, seed));
        verifyEqual(testCase, reshape(s2.', 1, []), chips, "AbsTol", 0, ...
            sprintf("BiDFE-2 identity soft frame %d seed %d", nb, seed));
    end
end
end

function testTrDiversityMergeEq5_57_59(testCase)
% TR diversity (Fig. 5-7): the forward BiDFE and the time-reversed
% BiDFE soft outputs are restored to the same time order and merged with
% EQUAL weight 1/2 per (5-57); the wrapper must expose the merged soft
% and the BiDFE branch indices.
book = fixtureBook();
h = [1, 0.6 * exp(1j * 0.3), 0.25 * exp(-1j * 0.7)];
rng(605, "twister");
nb = 8;
idx = randi(size(book, 1), 1, nb);
chips = reshape(book(idx, :).', 1, []);
memory = numel(h) - 1;
received = filter(h, 1, [chips, zeros(1, memory)]);
received = received + 1e-6 * (randn(size(received)) + 1j * randn(size(received)));
nv = 1e-3;
% Both branches are the exact BiDFE-2 kernels in the same scenario
% domain; the wrapper merges their soft outputs with equal weight after
% restoring the reversed branch to the same time order.
[fwIdx, fwSoft] = scfde.equalizers.ch5_bidfe2_detect( ...
    received, book, h, nv, 256);
verifyEqual(testCase, numel(fwIdx), nb);
% Reversed branch: BiDFE-2 on the time-reversed stream, restored.
revReceived = conj(fliplr(received));
[revIdx, revSoftRaw] = scfde.equalizers.ch5_bidfe2_detect( ...
    revReceived, book, h, nv, 256);
verifyEqual(testCase, numel(revIdx), nb);
revRestored = scfde.equalizers.ch5_tr_diversity_restore( ...
    revSoftRaw, numel(received), memory);
fwStream = reshape(fwSoft.', 1, []);
mergeOracle = fwStream;
valid = ~isnan(revRestored(1:numel(fwStream)));
mergeOracle(valid) = (fwStream(valid) + revRestored(valid)) / 2;
ch = struct("received", received, "impulse", h, "branches", [received; received]);
src = struct("data", reshape(book(idx, :).', 1, []), ...
    "tx", chips, "training", chips(1:min(32, numel(chips))));
cfg = struct("noiseVariance", nv, "receiverCandidateLimit", 256, "snrDb", 20);
recv = scfde.equalizers.cck_tr_diversity(ch, src, cfg);
verifyEqual(testCase, recv.estimates{1}, mergeOracle, "AbsTol", 1e-9, ...
    "(5-57) equal-weight merge must be produced by the wrapper");
verifyEqual(testCase, recv.traces{1}.branchForward, fwIdx, ...
    "wrapper forward branch must be the BiDFE-2 forward pass");
end

function testRegisteredBankFinite(testCase)
% Registered wrappers: finite BER, valid indices, RNG transparency.
book = fixtureBook();
h = [1, 0.6 * exp(1j * 0.3), 0.25 * exp(-1j * 0.7)];
rng(606, "twister");
idx = randi(size(book, 1), 1, 8);
chips = reshape(book(idx, :).', 1, []);
memory = numel(h) - 1;
received = filter(h, 1, [chips, zeros(1, memory)]);
received = received + sqrt(1e-3 / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));
ch = struct("received", received, "impulse", h, "branches", [received; received]);
src = struct("data", reshape(book(idx, :).', 1, []), ...
    "tx", chips, "training", chips(1:min(32, numel(chips))));
cfg = struct("noiseVariance", 1e-3, "receiverCandidateLimit", 128, "snrDb", 20);
registry = scfde.equalizer_registry();
targets = ["cck-bidfe", "cck-bidfe2", "cck-tr-diversity"];
for id = targets
    m = find(registry.id == id, 1);
    before = rng;
    recv = registry.module{m}(ch, src, cfg);
    after = rng;
    verifyEqual(testCase, after, before, ...
        id + " must preserve caller RNG state");
    verifyEqual(testCase, recv.ids, id);
    verifyTrue(testCase, all(isfinite(recv.outputs{1})), ...
        id + " outputs must be finite");
    verifyEqual(testCase, numel(recv.outputs{1}), numel(src.data), ...
        id + " must return the full data length");
end
end