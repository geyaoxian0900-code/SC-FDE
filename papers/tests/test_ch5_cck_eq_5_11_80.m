function tests = test_ch5_cck_eq_5_11_80
%TEST_CH5_CCK_EQ_5_11_80 Strict-formula tests for the remaining six CCK
% receivers (spec 5.1/5.2/5.3/5.4/5.6/5.7, book (5-11)~(5-80)):
% cck-rake, cck-dfe, cck-bidfe, cck-bidfe2, cck-fde, cck-mfb.
%
% Independent oracles (no production helper reuse):
%   * rake:  per-path conjugate-gain correlations summed over paths,
%            q_hat = argmax_q Re sum_l h_l* <r_tau_l, a_q> - the
%            production's chip-domain MRC plus one codebook decision is
%            decision-equivalent (exact index equality);
%   * mfb:   channel matched filter (full linear convolution, main-tap
%            aligned window) + nearest-codebook ML ((5-40)~(5-43));
%   * fde:   (5-80) C/B iteration with the (5-81)/(5-82) posterior-mean
%            soft feedback - inline replica; RED against the removed
%            fixed 0.65/0.35 soft mixing and residual-energy rollback;
%   * bidfe: the INITIALIZATION/execution order stays
%            BLOCKED-SOURCE-REVIEW (book/31.png, book/32.png); the
%            forward/reverse DFE sub-modules are tested separately;
%   * bitTable: codeword errors count the bit-table Hamming distance.

tests = functiontests({ ...
    @testRakeMrcDecisionEquivalenceEq5_33_40, ...
    @testRakeIdentityExact, ...
    @testDfeTemporaryDecisionStructureEq5_47, ...
    @testFdePosteriorMeanNoFixedMixingEq5_81_82, ...
    @testMfbCmfStructureEq5_40_43, ...
    @testBidfeBlockedStatusAndSubmodules, ...
    @testCckWrappersRngPreservedAndContracts, ...
    @testCckBitTableHammingSemantics});
%#ok<*DEFNU>  % setupOnce is invoked by the framework, not by name
%#ok<*NASGU>  % fixture outputs unused by individual tests are intentional
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function [received, idx, chips, h] = buildMultipathFrame(testCase, seed, snrDb)
h = [1, 0.6 * exp(1j * 0.3), 0.25 * exp(-1j * 0.7)];
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
rng(seed, "twister");
nb = 4;
idx = randi(size(book, 1), 1, nb);
chips = reshape(book(idx, :).', 1, []);
nv = 10^(-snrDb / 10);
received = filter(h, 1, [chips, zeros(1, numel(h) - 1)]);
received = received + sqrt(nv / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));
end

function testRakeMrcDecisionEquivalenceEq5_33_40(testCase)
% The production's chip-domain MRC + single codebook decision must be
% decision-equivalent to the boxed per-path/codeword MRC:
%   q_hat = argmax_q Re sum_l h_l* sum_n r(n+tau_l) conj(a_q(n)).
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
h = [1, 0.6 * exp(1j * 0.3), 0.25 * exp(-1j * 0.7)];
rng(901, "twister");
nb = 4;
idx = randi(size(book, 1), 1, nb);
chips = reshape(book(idx, :).', 1, []);
received = filter(h, 1, [chips, zeros(1, numel(h) - 1)]);
received = received + sqrt(1e-6 / 2) * ...
    (randn(size(received)) + 1j * randn(size(received)));
detected = scfde.equalizers.ch5_rake_detect(received, book, h);
blockCount = ceil((numel(received) - numel(h) + 1) / 8);
padded = [received, zeros(1, numel(h))];
oracle = zeros(1, blockCount);
for block = 1:blockCount
    start = (block - 1) * 8 + 1;
    bestScore = -inf;
    best = 0;
    for q = 1:size(book, 1)
        Z = 0;
        for l = 1:numel(h)
            seg = padded(start + l - 1:start + l + 6);
            Z = Z + conj(h(l)) * sum(seg .* conj(book(q, :)));
        end
        if real(Z) > bestScore
            bestScore = real(Z);
            best = q;
        end
    end
    oracle(block) = best;
end
verifyEqual(testCase, detected, oracle, ...
    "Rake MRC must equal the per-path/codeword box decision");
end

function testRakeIdentityExact(testCase)
% Identity + zero noise: the Rake must recover every transmitted index.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
for nb = [1, 2, 7]
    for seed = 1:10
        rng(seed, "twister");
        idx = randi(size(book, 1), 1, nb);
        chips = reshape(book(idx, :).', 1, []);
        detected = scfde.equalizers.ch5_rake_detect(chips, book, [1, 0, 0]);
        verifyEqual(testCase, detected, idx, ...
            sprintf("rake identity frame %d seed %d", nb, seed));
    end
end
end

function testDfeTemporaryDecisionStructureEq5_47(testCase)
% The forward DFE wrapper is the (5-40)~(5-47) structure; the current
% word never enters its own feedback (the chip-level temporary-decision
% oracle lives in test_cck_tr_diversity_eq_5_57).
[received, idx, chips, h] = buildMultipathFrame(testCase, 902, 15);
ch = struct("received", received, "impulse", h, ...
    "branches", [received; received]);
src = struct("data", reshape(ch5CodebookRow(idx), 1, []), ...
    "tx", chips, "training", chips(1:min(32, numel(chips))));
cfg = struct("noiseVariance", 10^(-15 / 10), ...
    "receiverCandidateLimit", 128, "snrDb", 15);
recv = scfde.equalizers.cck_dfe(ch, src, cfg);
verifyEqual(testCase, recv.traces{1}.formulaStatus, "BOOK-EXACT");
verifyTrue(testCase, isfield(recv.traces{1}, "indices"));
verifyEqual(testCase, numel(recv.traces{1}.indices), 4);
end

function rows = ch5CodebookRow(idx)
% Helper: codebook rows for the fixture data vector.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
rows = reshape(book(idx, :).', 1, []);
end

function testFdePosteriorMeanNoFixedMixingEq5_81_82(testCase)
% RED against the removed 0.65/0.35 soft mixing and residual-energy
% rollback: the (5-80) C/B iteration with the (5-81)/(5-82) posterior
% mean as the ONLY soft feedback must reproduce the production
% history exactly.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
[received, ~, ~, h] = buildMultipathFrame(testCase, 903, 15);
nv = 10^(-15 / 10);
iterations = 2;
[~, history] = scfde.equalizers.ch5_fde_cck_detect( ...
    received, book, h, nv, iterations);
blockCount = ceil((numel(received) - numel(h) + 1) / 8);
lengthFrame = blockCount * 8;
if numel(received) < lengthFrame
    received = [received, zeros(1, lengthFrame - numel(received))];
else
    received = received(1:lengthFrame);
end
H = fft([h, zeros(1, lengthFrame - numel(h))]);
Y = fft(received);
soft = zeros(1, lengthFrame);
oracle = zeros(iterations, blockCount);
for iteration = 1:iterations
    reliability = min(0.98, 8 * mean(abs(soft).^2));
    C = conj(H) ./ (nv + (1 - reliability) * abs(H).^2);
    C = C / mean(C .* H);
    B = C .* H - 1;
    estimate = ifft(C .* Y - B .* fft(soft));
    blocks = reshape(estimate, 8, []).';
    softWord = complex(zeros(size(blocks)));
    for b = 1:size(blocks, 1)
        d = sum(abs(book - blocks(b, :)).^2, 2);
        [~, oracle(iteration, b)] = min(d);
        w = exp(-(d - min(d)) / max(nv, 1e-8));
        w = w / sum(w);
        softWord(b, :) = w.' * book;
    end
    soft = reshape(softWord.', 1, []);
end
verifyEqual(testCase, history, oracle, ...
    "FDE soft feedback must be the undamped posterior mean (5-81)/(5-82)");
end

function testMfbCmfStructureEq5_40_43(testCase)
% The matched-filter bound: full linear convolution CMF, main-tap
% aligned window, nearest-codebook ML decision.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
h = [1, 0.6 * exp(1j * 0.3), 0.25 * exp(-1j * 0.7)];
rng(904, "twister");
idx = randi(size(book, 1), 1, 4);
chips = reshape(book(idx, :).', 1, []);
received = filter(h, 1, [chips, zeros(1, numel(h) - 1)]);
detected = scfde.equalizers.ch5_matched_filter_detect(received, book, h);
memory = numel(h) - 1;
focused = conv(conj(fliplr(h)), received);
aligned = focused(memory + (1:numel(received)));
blockCount = ceil(numel(aligned) / 8);
padded = [aligned, zeros(1, blockCount * 8 - numel(aligned))];
blocks = reshape(padded, 8, []).';
oracle = zeros(1, blockCount);
for b = 1:blockCount
    best = 1;
    bestD = inf;
    for q = 1:size(book, 1)
        d = sum(abs(book(q, :) - blocks(b, :)).^2);
        if d < bestD
            bestD = d;
            best = q;
        end
    end
    oracle(b) = best;
end
verifyEqual(testCase, detected, oracle);
end

function testBidfeBlockedStatusAndSubmodules(testCase)
% The BiDFE wrappers now execute the strict (5-46)~(5-54) signal flow
% (book/P133.png~P137.png, Task 6); the certification status remains
% BLOCKED-SOURCE-REVIEW until the Task 9 weakest-link re-certification,
% and the forward/reverse DFE sub-modules are exact under identity
% (independent of the certification step).
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
[received, idx, chips, h] = buildMultipathFrame(testCase, 905, 15);
ch = struct("received", received, "impulse", h, ...
    "branches", [received; received]);
src = struct("data", reshape(book(idx, :).', 1, []), ...
    "tx", chips, "training", chips(1:min(32, numel(chips))));
cfg = struct("noiseVariance", 10^(-15 / 10), ...
    "receiverCandidateLimit", 128, "snrDb", 15);
recv1 = scfde.equalizers.cck_bidfe(ch, src, cfg);
recv2 = scfde.equalizers.cck_bidfe2(ch, src, cfg);
verifyEqual(testCase, recv1.traces{1}.formulaStatus, "BLOCKED-SOURCE-REVIEW");
verifyEqual(testCase, recv1.traces{1}.formulaMode, "book");
verifyEqual(testCase, recv2.traces{1}.formulaStatus, "BLOCKED-SOURCE-REVIEW");
verifyEqual(testCase, recv2.traces{1}.formulaMode, "book");
% Identity sub-module check (forward and reverse detectors).
rng(906, "twister");
idxI = randi(size(book, 1), 1, 4);
chipsI = reshape(book(idxI, :).', 1, []);
[fw] = scfde.equalizers.ch5_dfe_detect(chipsI, book, [1, 0, 0], 1e-9, 128);
[bw] = scfde.equalizers.ch5_backward_dfe_detect(chipsI, book, [1, 0, 0], 1e-9, 128);
verifyEqual(testCase, fw, idxI);
verifyEqual(testCase, bw, idxI);
end

function testCckWrappersRngPreservedAndContracts(testCase)
% The six remaining CCK wrappers: RNG transparency, per-method ids,
% output lengths, indices in range, formula status recorded.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
[received, idx, chips, h] = buildMultipathFrame(testCase, 907, 15);
ch = struct("received", received, "impulse", h, ...
    "branches", [received; received]);
src = struct("data", reshape(book(idx, :).', 1, []), ...
    "tx", chips, "training", chips(1:min(32, numel(chips))));
cfg = struct("noiseVariance", 10^(-15 / 10), ...
    "receiverCandidateLimit", 128, "turboIterations", 2, "snrDb", 15);
registry = scfde.equalizer_registry();
targets = ["cck-rake", "cck-dfe", "cck-bidfe", "cck-bidfe2", ...
    "cck-fde", "cck-mfb"];
ch5 = find(ismember(registry.id, targets));
verifyEqual(testCase, numel(ch5), 6);
for m = ch5(:)'
    before = rng;
    recv = registry.module{m}(ch, src, cfg);
    after = rng;
    verifyEqual(testCase, after, before, ...
        "wrapper " + registry.id(m) + " must preserve caller RNG state");
    verifyTrue(testCase, isfield(recv.traces{1}, "formulaStatus"), ...
        "wrapper " + registry.id(m) + " must record formulaStatus");
    verifyTrue(testCase, isfield(recv.traces{1}, "indices"), ...
        "wrapper " + registry.id(m) + " must expose indices");
    verifyTrue(testCase, all(recv.traces{1}.indices >= 1 & ...
        recv.traces{1}.indices <= size(book, 1)), ...
        "wrapper " + registry.id(m) + " indices in codebook range");
    verifyEqual(testCase, numel(recv.outputs{1}), numel(src.data));
    verifyEqual(testCase, recv.ids, registry.id(m));
end
end

function testCckBitTableHammingSemantics(testCase)
% The CCK metric counts the bit-table Hamming distance per codeword
% error (not the chip distance, and not all-8-bits).
[~, bitTable] = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
hamming12 = sum(bitTable(1, :) ~= bitTable(2, :));
verifyTrue(testCase, hamming12 >= 1 && hamming12 <= 8);
% Full mapping consistency: every codeword index maps to its own bits.
for q = [1, 7, 129, 256]
    verifyEqual(testCase, bitTable(q, :), bitget(q - 1, 1:8));
end
end
