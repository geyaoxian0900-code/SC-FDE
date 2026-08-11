function tests = test_cck_identity_all_seeds
%TEST_CCK_IDENTITY_ALL_SEEDS CCK identity + zero-noise correctness gate.
%
% The audit discovered identity BER > 0 for several CCK equalizers while
% the main suite stayed green, so this gate locks the invariants:
%   1) every registered CCK equalizer, frame lengths 1/2/7/8/9 blocks,
%      seeds 1..100, identity channel + zero noise -> BER exactly 0 and
%      the module's own index trace matches the transmitted codewords;
%   2) bidirectional stages forward / reverse / combined / refined are
%      N/N for every block (reverse path regression: the tailOffset
%      segment model fixed 0/2700 identity blocks);
%   3) cck-fde must expose trace.indices (it previously crashed with an
%      empty .* product on 1-block frames and silently fell back to the
%      audit's correlation oracle).

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
addpath(fullfile(papersDir, "common"));
addpath(fullfile(papersDir, "engineering_simulation"));
testCase.TestData.papersDir = papersDir;
end

function testIdentityAllFrameLengthsAndSeeds(testCase)
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
registry = scfde.equalizer_registry();
methods = registry.id(registry.scenario == "cck");
nblocksList = [1, 2, 7, 8, 9];
seedMax = 100;
checked = 0;
for nb = nblocksList
    for seed = 1:seedMax
        rng(seed, "twister");
        idx = randi(size(book, 1), 1, nb);
        chips = reshape(book(idx, :).', 1, []);
        ch = struct("received", chips, "impulse", [1, 0, 0], ...
            "branches", [chips; chips]);
        src = struct("data", reshape(book(idx, :).', 1, []), ...
            "tx", chips, "training", chips(1:min(32, numel(chips))));
        cfg = struct("noiseVariance", 1e-9, "receiverCandidateLimit", 128, ...
            "turboIterations", 3, "snrDb", 99);
        for m = 1:numel(methods)
            module = registry.module{find(registry.id == methods(m), 1)};
            r = module(ch, src, cfg);
            verifyTrue(testCase, isfield(r.traces{1}, "indices"), ...
                sprintf("%s trace must expose indices (frame %d, seed %d)", ...
                methods(m), nb, seed));
            det = r.traces{1}.indices(:).';
            det = det(1:min(nb, numel(det)));
            verifyEqual(testCase, det, idx(1:numel(det)), ...
                sprintf("%s identity BER ~= 0 (frame %d, seed %d)", methods(m), nb, seed));
            checked = checked + 1;
        end
    end
end
fprintf("test_cck_identity_all_seeds: %d (method, frame, seed) combos\n", checked);
end

function testBidirectionalAllStages(testCase)
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
nblocksList = [1, 2, 7, 8, 9];
seedMax = 100;
for nb = nblocksList
    for seed = 1:seedMax
        rng(seed, "twister");
        idx = randi(size(book, 1), 1, nb);
        chips = reshape(book(idx, :).', 1, []);
        [fw, fwS] = scfde.equalizers.ch5_dfe_detect(chips, book, [1, 0, 0], 1e-9, 128);
        [bw, bwS] = scfde.equalizers.ch5_backward_dfe_detect(chips, book, [1, 0, 0], 1e-9, 128);
        bi1 = scfde.equalizers.ch5_fuse_scores(fwS, bwS);
        bi2 = scfde.equalizers.ch5_bidirectional_refine(chips, book, [1, 0, 0], bi1, 1e-9, 128);
        verifyEqual(testCase, fw, idx, sprintf("forward stage (frame %d, seed %d)", nb, seed));
        verifyEqual(testCase, bw, idx, sprintf("reverse stage (frame %d, seed %d)", nb, seed));
        verifyEqual(testCase, bi1, idx, sprintf("combined stage (frame %d, seed %d)", nb, seed));
        verifyEqual(testCase, bi2, idx, sprintf("refined stage (frame %d, seed %d)", nb, seed));
    end
end
end
