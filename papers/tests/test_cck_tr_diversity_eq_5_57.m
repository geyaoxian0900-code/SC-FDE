function tests = test_cck_tr_diversity_eq_5_57
%TEST_CCK_TR_DIVERSITY_EQ_5_57 Strict-formula tests for (5-57)~(5-59).
%
% Independent oracles (no production helper reuse):
%   * merge   = elementwise (A+B)/2, equal weights, swap-invariant,
%               linear (a perturbation splits as delta/2), degenerate
%               equal inputs exact, NaN head falls back to the forward
%               branch alone;
%   * restore = rev[] = conj(fliplr) per reversed block placed at the
%               original chip positions the reversed window observes;
%   * detector soft outputs = identity frames exact + a linear-
%               convolution past-spill oracle for the forward branch;
%   * wrapper = identity+zero-noise exact indices/outputs/estimates,
%               aligned-merge wiring against an inline restore/combine
%               oracle, codeword->bitTable Hamming bit errors, RNG
%               preservation, trace formula-status fields.
% Negative variants (RED against the previous production path): the old
% wrapper emitted a multi-branch matched-filter output with a hard
% codebook decision; the new path must average the two restored chip
% streams (a soft midpoint off the axial alphabet) and must not return
% either branch alone.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testCombinerEqualWeightAverage(testCase)
rng(21, "twister");
a = randn(3, 8) + 1j * randn(3, 8);
b = randn(3, 8) + 1j * randn(3, 8);
merged = scfde.equalizers.ch5_tr_diversity_combine(a, reshape(b.', 1, []));
verifyEqual(testCase, merged, reshape(((a + b) / 2).', 1, []), "AbsTol", 0);
end

function testCombinerSwapInvariance(testCase)
rng(22, "twister");
a = randn(2, 8) + 1j * randn(2, 8);
b = randn(2, 8) + 1j * randn(2, 8);
sA = reshape(a.', 1, []);
sB = reshape(b.', 1, []);
verifyEqual(testCase, ...
    scfde.equalizers.ch5_tr_diversity_combine(a, sB), ...
    scfde.equalizers.ch5_tr_diversity_combine(b, sA), "AbsTol", 0);
end

function testCombinerPerturbationLinearity(testCase)
% y(k) = (A(k)+B(k))/2 is linear: perturbing one branch by delta moves
% the merged output by exactly delta/2.
rng(23, "twister");
a = randn(2, 8) + 1j * randn(2, 8);
b = randn(2, 8) + 1j * randn(2, 8);
delta = (0.5 + 0.25j) * ones(2, 8);
base = scfde.equalizers.ch5_tr_diversity_combine(a, reshape(b.', 1, []));
shifted = scfde.equalizers.ch5_tr_diversity_combine( ...
    a + delta, reshape(b.', 1, []));
verifyEqual(testCase, shifted, base + reshape((delta / 2).', 1, []), "AbsTol", 1e-14);
end

function testCombinerDegenerateEqualInputs(testCase)
rng(24, "twister");
a = randn(3, 8) + 1j * randn(3, 8);
sA = reshape(a.', 1, []);
verifyEqual(testCase, scfde.equalizers.ch5_tr_diversity_combine(a, sA), ...
    sA, "AbsTol", 0);
end

function testCombinerHeadRegionFallsBackToForward(testCase)
% The reversed window does not cover the first `memory` frame chips
% (restore returns NaN there); the merged output must take the forward
% branch alone on the head and the exact average elsewhere.
rng(25, "twister");
a = randn(2, 8) + 1j * randn(2, 8);
rev = nan(1, 20);
rev(5:20) = randn(1, 16) + 1j * randn(1, 16);
fw = reshape(a.', 1, []);
merged = scfde.equalizers.ch5_tr_diversity_combine(a, rev);
verifyTrue(testCase, all(isfinite(merged)));
verifyEqual(testCase, merged(1:4), fw(1:4), "AbsTol", 0);
verifyEqual(testCase, merged(5:16), (fw(5:16) + rev(5:16)) / 2, "AbsTol", 0);
end

function testCombinerNegativeNotSingleBranchAndSoft(testCase)
% Negative (RED against the old production path): the merged output
% must be a soft average - equal to NEITHER branch and off the axial
% QPSK alphabet wherever the branches differ (the old wrapper returned
% hard codebook chips from one fused index decision).
a = [1, 1j, -1, -1j, 1, 1j, -1, -1j];
b = [1j, -1, -1j, 1, 1j, -1, -1j, 1];
merged = scfde.equalizers.ch5_tr_diversity_combine(a, b);
verifyTrue(testCase, any(abs(merged - a) > 0), ...
    "merged output must not be the forward branch alone");
verifyTrue(testCase, any(abs(merged - b) > 0), ...
    "merged output must not be the reversed branch alone");
re = real(merged);
im = imag(merged);
sliced = (abs(re) >= abs(im)) .* sign(re) + ...
    1j * (abs(im) > abs(re)) .* sign(im);
verifyTrue(testCase, any(abs(sliced - merged) > 0), ...
    "merged output must be a soft average, not hard-sliced chips");
end

function testDetectorZeroPaddingNoStateEq5_47(testCase)
% Negative regression: zero padding must NOT create channel state.
% [1], [1,0] and [1,0,0] must produce IDENTICAL soft outputs and
% indices for the same received frame (the old numel-based memory
% turned the zero padding into a phantom 2-tap inter-block state).
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
channels = {[1], [1, 0], [1, 0, 0]};
for nb = [1, 2, 5]
    for seed = 1:5
        rng(seed, "twister");
        idx = randi(size(book, 1), 1, nb);
        chips = reshape(book(idx, :).', 1, []);
        baseFw = [];
        baseBw = [];
        baseFwSoft = [];
        baseBwSoft = [];
        for c = 1:numel(channels)
            h = channels{c};
            [fw, ~, fwSoft] = scfde.equalizers.ch5_dfe_detect( ...
                chips, book, h, 1e-9, 128);
            [bw, ~, bwSoft] = scfde.equalizers.ch5_backward_dfe_detect( ...
                chips, book, h, 1e-9, 128);
            if isempty(baseFw)
                baseFw = fw;
                baseBw = bw;
                baseFwSoft = fwSoft;
                baseBwSoft = bwSoft;
            else
                msg = sprintf("zero-padded channel frame %d seed %d", nb, seed);
                verifyEqual(testCase, fw, baseFw, msg);
                verifyEqual(testCase, bw, baseBw, msg);
                verifyEqual(testCase, fwSoft, baseFwSoft, "AbsTol", 0, msg);
                verifyEqual(testCase, bwSoft, baseBwSoft, "AbsTol", 0, msg);
            end
        end
    end
end
end

function testDetectorNonzeroTailProducesStateEq5_47(testCase)
% Negative regression: a REAL tail tap must produce inter-block state.
% For the same zero-tail received frame, modeling a nonzero tail tap
% must change the reverse soft outputs versus the zero-tail channel
% (the tail spill must be subtracted, not silently ignored).
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
rng(412, "twister");
nb = 4;
idx = randi(size(book, 1), 1, nb);
chips = reshape(book(idx, :).', 1, []);
received = filter([1, 0, 0], 1, [chips, zeros(1, 2)]);
[~, ~, softZero] = scfde.equalizers.ch5_backward_dfe_detect( ...
    received, book, [1, 0, 0], 1e-9, 256);
[~, ~, softTail] = scfde.equalizers.ch5_backward_dfe_detect( ...
    received, book, [1, 0, 0.25], 1e-9, 256);
verifyTrue(testCase, any(abs(softZero(:) - softTail(:)) > 1e-12), ...
    "a nonzero tail tap must produce inter-block state (outputs must differ)");
end

function testPaddedAndUnpaddedChannelsIdenticalEq5_57(testCase)
% Negative regression: a channel with trailing zeros must behave
% EXACTLY like its effective form - identical soft outputs, indices
% and wrapper merged outputs for the same received frame.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
hEff = [1, 0.5, 0.25 * exp(1j * 0.4)];
hPad = [hEff, 0, 0];
rng(411, "twister");
nb = 4;
idx = randi(size(book, 1), 1, nb);
chips = reshape(book(idx, :).', 1, []);
received = filter(hEff, 1, [chips, zeros(1, numel(hEff) - 1)]);
received = received + sqrt(1e-6 / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));
[fwA, ~, fwSoftA] = scfde.equalizers.ch5_dfe_detect( ...
    received, book, hEff, 1e-6, 256);
[fwB, ~, fwSoftB] = scfde.equalizers.ch5_dfe_detect( ...
    received, book, hPad, 1e-6, 256);
verifyEqual(testCase, fwA, fwB);
verifyEqual(testCase, fwSoftA, fwSoftB, "AbsTol", 0);
[bwA, ~, bwSoftA] = scfde.equalizers.ch5_backward_dfe_detect( ...
    received, book, hEff, 1e-6, 256);
[bwB, ~, bwSoftB] = scfde.equalizers.ch5_backward_dfe_detect( ...
    received, book, hPad, 1e-6, 256);
verifyEqual(testCase, bwA, bwB);
verifyEqual(testCase, bwSoftA, bwSoftB, "AbsTol", 0);
% Wrapper level: merged outputs and decisions must be identical.
chA = struct("received", received, "impulse", hEff, ...
    "branches", [received; received]);
src = struct("data", reshape(book(idx, :).', 1, []), ...
    "tx", chips, "training", chips(1:min(32, numel(chips))));
cfg = struct("noiseVariance", 1e-6, "receiverCandidateLimit", 256, "snrDb", 60);
recvA = scfde.equalizers.cck_tr_diversity(chA, src, cfg);
chB = chA;
chB.impulse = hPad;
recvB = scfde.equalizers.cck_tr_diversity(chB, src, cfg);
verifyEqual(testCase, recvA.outputs{1}, recvB.outputs{1}, "AbsTol", 0);
verifyEqual(testCase, recvA.estimates{1}, recvB.estimates{1}, "AbsTol", 0);
verifyEqual(testCase, recvA.traces{1}.indices, recvB.traces{1}.indices);
end

function testCombinerShapeMismatchThrows(testCase)
verifyError(testCase, @() scfde.equalizers.ch5_tr_diversity_combine( ...
    zeros(2, 8), zeros(1, 15)), "SCFDE:TrDiversityCombineLength");
verifyError(testCase, @() scfde.equalizers.ch5_tr_diversity_combine( ...
    zeros(2, 7), zeros(1, 16)), "SCFDE:TrDiversityCombineShape");
end

function testRestorePlacesReversedSoftAtSameTimeOrder(testCase)
% Oracle straight from the book convention rev[] = conj(fliplr) and the
% reversed-window chip mapping k = frameLength - 8*j + 1 .. + 8: row j
% covers the response tail segment of original block N-j+1.  With the
% scenario frame convention (frameLength = 8*blockCount + memory) the
% first `memory` chips have no reversed window and stay NaN.
rng(31, "twister");
bw = randn(2, 8) + 1j * randn(2, 8);
out = scfde.equalizers.ch5_tr_diversity_restore(bw, 20, 4);
oracle = nan(1, 20);
for j = 1:2
    k0 = 20 - 8 * j + 1;
    oracle(k0:k0 + 7) = conj(fliplr(bw(j, :)));
end
verifyTrue(testCase, isequal(isnan(out), isnan(oracle)));
mask = ~isnan(out);
verifyEqual(testCase, out(mask), oracle(mask), "AbsTol", 0);
end

function testRestoreNoTailFrameFullCoverage(testCase)
% Frames without a channel-tail (frameLength = 8*blockCount, the
% identity-gate convention) are fully covered: no NaN head.
rng(32, "twister");
bw = randn(2, 8) + 1j * randn(2, 8);
out = scfde.equalizers.ch5_tr_diversity_restore(bw, 16, 4);
verifyTrue(testCase, all(isfinite(out)));
oracle = nan(1, 16);
for j = 1:2
    k0 = 16 - 8 * j + 1;
    oracle(k0:k0 + 7) = conj(fliplr(bw(j, :)));
end
verifyEqual(testCase, out, oracle, "AbsTol", 0);
end

function testRestoreInvalidInputsThrow(testCase)
verifyError(testCase, @() scfde.equalizers.ch5_tr_diversity_restore( ...
    zeros(2, 7), 20, 4), "SCFDE:TrDiversityRestoreShape");
verifyError(testCase, @() scfde.equalizers.ch5_tr_diversity_restore( ...
    zeros(2, 8), 15, 4), "SCFDE:TrDiversityRestoreLength");
verifyError(testCase, @() scfde.equalizers.ch5_tr_diversity_restore( ...
    zeros(2, 8), 20, -1), "SCFDE:TrDiversityRestoreMemory");
end

function testDetectorSoftOutputsIdentityExact(testCase)
% Independent oracle: under an identity channel both branches have no
% state spill, so the forward soft output equals the transmitted chips
% (row per block) and the raw reversed-domain soft output equals
% conj(fliplr(block N-j+1)) for reversed row j.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
for nb = [1, 2, 7]
    for seed = 1:10
        rng(seed, "twister");
        idx = randi(size(book, 1), 1, nb);
        chips = reshape(book(idx, :).', 1, []);
        [~, ~, fw] = scfde.equalizers.ch5_dfe_detect( ...
            chips, book, [1, 0, 0], 1e-9, 128);
        [~, ~, bw] = scfde.equalizers.ch5_backward_dfe_detect( ...
            chips, book, [1, 0, 0], 1e-9, 128);
        verifyEqual(testCase, fw, reshape(chips, 8, []).', "AbsTol", 0, ...
            sprintf("forward soft frame %d seed %d", nb, seed));
        expectedBw = complex(zeros(nb, 8));
        for j = 1:nb
            expectedBw(j, :) = conj(fliplr(book(idx(nb - j + 1), :)));
        end
        verifyEqual(testCase, bw, expectedBw, "AbsTol", 0, ...
            sprintf("reversed soft frame %d seed %d", nb, seed));
    end
end
end

function testForwardSoftCancelsPastSpillOnly(testCase)
% Independent linear-convolution oracle: with channel [1, 0.5, 0], the
% received sample of chip k is a(k) + 0.5*a(k-1).  Window 2 (samples
% 9..16) therefore contains the spill 0.5*w1(8) at its first chip; the
% forward soft output must remove exactly that spill and nothing else
% (zero noise, full codebook so block 1 is decided exactly).
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
h = [1, 0.5, 0];
rng(55, "twister");
w1 = book(randi(size(book, 1)), :);
w2 = book(randi(size(book, 1)), :);
chips = [w1, w2];
received = filter(h, 1, [chips, zeros(1, 2)]);
[~, ~, fw] = scfde.equalizers.ch5_dfe_detect(received, book, h, 1e-9, 256);
verifyTrue(testCase, size(fw, 1) >= 2);
obs2 = received(9:16);
spill = zeros(1, 8);
spill(1) = 0.5 * w1(8);
verifyEqual(testCase, fw(2, :), obs2 - spill, "AbsTol", 1e-12);
end

function testWrapperIdentityExactAllFrameLengths(testCase)
% The identity gate: index trace, hard outputs and merged soft
% estimates must all reproduce the transmitted codewords exactly.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
for nb = [1, 2, 7, 8, 9]
    for seed = 1:20
        rng(seed, "twister");
        idx = randi(size(book, 1), 1, nb);
        chips = reshape(book(idx, :).', 1, []);
        ch = struct("received", chips, "impulse", [1, 0, 0], ...
            "branches", [chips; chips]);
        src = struct("data", reshape(book(idx, :).', 1, []), ...
            "tx", chips, "training", chips(1:min(32, numel(chips))));
        cfg = struct("noiseVariance", 1e-9, ...
            "receiverCandidateLimit", 128, "snrDb", 99);
        recv = scfde.equalizers.cck_tr_diversity(ch, src, cfg);
        det = recv.traces{1}.indices(:).';
        verifyEqual(testCase, det, idx, ...
            sprintf("indices frame %d seed %d", nb, seed));
        verifyEqual(testCase, recv.outputs{1}, chips, "AbsTol", 0, ...
            sprintf("outputs frame %d seed %d", nb, seed));
        verifyEqual(testCase, recv.estimates{1}, chips, "AbsTol", 0, ...
            sprintf("estimates frame %d seed %d", nb, seed));
    end
end
end

function testWrapperMergesAlignedBranchOutputs(testCase)
% Wiring RED test: the wrapper's soft output must be EXACTLY the
% equal-weight average of the two BiDFE-2 branch streams restored to the
% same time order (inline restore/combine oracle).  The old wrapper
% merged plain forward/reversed DFE soft outputs and would fail here.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
imp = scfde.equalizers.ch5_short_turbo_channel();
memory = numel(imp) - 1;
nv = 10^(-10 / 10);
rng(87, "twister");
nb = 8;
idx = randi(size(book, 1), 1, nb);
chips = reshape(book(idx, :).', 1, []);
noise = sqrt(nv / 2) * (randn(1, numel(chips) + memory) + ...
    1j * randn(1, numel(chips) + memory));
received = filter(imp, 1, [chips, zeros(1, memory)]) + noise;
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received]);
src = struct("data", reshape(book(idx, :).', 1, []), ...
    "tx", chips, "training", chips(1:32));
cfg = struct("noiseVariance", nv, "receiverCandidateLimit", 128, "snrDb", 10);
recv = scfde.equalizers.cck_tr_diversity(ch, src, cfg);
% BiDFE-2 branches: forward on the stream, reversed on the time-reversed
% stream restored to the same time order.
[~, fw] = scfde.equalizers.ch5_bidfe2_detect(received, book, imp, nv, 128);
[~, bw] = scfde.equalizers.ch5_bidfe2_detect( ...
    conj(fliplr(received)), book, imp, nv, 128);
revStream = scfde.equalizers.ch5_tr_diversity_restore( ...
    bw, numel(received), memory);
fwStream = reshape(fw.', 1, []);
oracle = fwStream;
valid = ~isnan(revStream(1:numel(fwStream)));
oracle(valid) = (fwStream(valid) + revStream(valid)) / 2;
verifyEqual(testCase, recv.estimates{1}, oracle, "AbsTol", 0);
verifyEqual(testCase, numel(recv.estimates{1}), 64);
end

function testWrapperCodewordBitErrorsMatchBitTable(testCase)
% The CCK scenario metric maps detected indices to bits through the bit
% table; a codeword change must produce exactly the Hamming distance of
% the two bit rows (codewords 1 and 2 differ in exactly one bit).
[book, bitTable] = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
c1 = 1;
c2 = 2;
verifyTrue(testCase, sum(bitTable(c1, :) ~= bitTable(c2, :)) == 1);
det = zeros(1, 2);
for pair = 1:2
    if pair == 1, c = c1; else, c = c2; end
    chips = book(c, :);
    ch = struct("received", chips, "impulse", [1, 0, 0], ...
        "branches", [chips; chips]);
    src = struct("data", chips, "tx", chips, "training", chips);
    cfg = struct("noiseVariance", 1e-9, ...
        "receiverCandidateLimit", 128, "snrDb", 99);
    recv = scfde.equalizers.cck_tr_diversity(ch, src, cfg);
    det(pair) = recv.traces{1}.indices(1);
end
verifyEqual(testCase, det(1), c1);
verifyEqual(testCase, det(2), c2);
verifyEqual(testCase, sum(bitTable(det(1), :) ~= bitTable(det(2), :)), ...
    sum(bitTable(c1, :) ~= bitTable(c2, :)));
end

function testWrapperRngPreservedAndTraceStatus(testCase)
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
imp = scfde.equalizers.ch5_short_turbo_channel();
memory = numel(imp) - 1;
nv = 10^(-10 / 10);
rng(88, "twister");
idx = randi(size(book, 1), 1, 8);
chips = reshape(book(idx, :).', 1, []);
received = filter(imp, 1, [chips, zeros(1, memory)]) + ...
    sqrt(nv / 2) * (randn(1, numel(chips) + memory) + ...
    1j * randn(1, numel(chips) + memory));
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received]);
src = struct("data", reshape(book(idx, :).', 1, []), ...
    "tx", chips, "training", chips(1:32));
cfg = struct("noiseVariance", nv, "receiverCandidateLimit", 128, "snrDb", 10);
before = rng;
recv = scfde.equalizers.cck_tr_diversity(ch, src, cfg);
after = rng;
verifyEqual(testCase, after, before, ...
    "wrapper must not mutate caller RNG state");
trace = recv.traces{1};
verifyTrue(testCase, isfield(trace, "indices"));
verifyTrue(testCase, isfield(trace, "combinerFormulaStatus"));
verifyEqual(testCase, trace.combinerFormulaStatus, "BOOK-EXACT");
verifyEqual(testCase, trace.headRegionStatus, "ENGINEERING");
verifyEqual(testCase, trace.branchSoftOutputStatus, "ALG-EQUIV");
verifyEqual(testCase, recv.ids, "cck-tr-diversity");
verifyEqual(testCase, recv.names, "CCK-TR-Diversity");
end

function testWrapperMultipathWellFormed(testCase)
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
imp = scfde.equalizers.ch5_short_turbo_channel();
memory = numel(imp) - 1;
nv = 10^(-8 / 10);
rng(89, "twister");
idx = randi(size(book, 1), 1, 8);
chips = reshape(book(idx, :).', 1, []);
received = filter(imp, 1, [chips, zeros(1, memory)]) + ...
    sqrt(nv / 2) * (randn(1, numel(chips) + memory) + ...
    1j * randn(1, numel(chips) + memory));
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received]);
src = struct("data", reshape(book(idx, :).', 1, []), ...
    "tx", chips, "training", chips(1:32));
cfg = struct("noiseVariance", nv, "receiverCandidateLimit", 128, "snrDb", 8);
recv = scfde.equalizers.cck_tr_diversity(ch, src, cfg);
det = recv.traces{1}.indices(:).';
verifyEqual(testCase, numel(det), 8);
verifyTrue(testCase, all(det >= 1 & det <= size(book, 1)));
verifyEqual(testCase, numel(recv.outputs{1}), 64);
verifyEqual(testCase, size(recv.estimates{1}), [1, 64]);
end
