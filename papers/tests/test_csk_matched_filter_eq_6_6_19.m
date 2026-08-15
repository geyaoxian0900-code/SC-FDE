function tests = test_csk_matched_filter_eq_6_6_19
%TEST_CSK_MATCHED_FILTER_EQ_6_6_19 Strict-formula tests for
% csk-matched-filter (spec 6.1, book (6-6)~(6-12), (6-16)~(6-19)).
%
% Independent oracles (no production helper reuse):
%   * root sequence: deterministic + low autocorrelation sidelobes
%     (the selection criterion);
%   * codebook: the M rows are the cyclic shifts of the root;
%   * (6-9) demodulation correlation: theta = (1/G) Re{ F^{-1}[(F s)*
%     .* (F alpha)] } peaks exactly at the true shift for a noiseless
%     identity symbol, and the production dictionary decision equals
%     the correlation peak under an identity channel;
%   * identity/noiseless full recovery, user/symbol index mapping,
%     bit-table mapping, multi-user input dimension, RNG contract.

tests = functiontests({ ...
    @testRootSequenceDeterministicAndLowSidelobes, ...
    @testCodebookIsCyclicShiftsEq6_6, ...
    @testDemodCorrelationPeakEq6_9, ...
    @testDictionaryDecisionEqualsCorrelationUnderIdentity, ...
    @testWrapperIdentityExact, ...
    @testMultiUserInputDimension, ...
    @testBitTableMapping, ...
    @testWrapperRngPreservedAndContracts});
%#ok<*DEFNU>  % setupOnce is invoked by the framework, not by name
%#ok<*NASGU>  % fixture outputs unused by individual tests are intentional
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testRootSequenceDeterministicAndLowSidelobes(testCase)
rootA = scfde.equalizers.ch6_select_csk_root(63);
rootB = scfde.equalizers.ch6_select_csk_root(63);
verifyEqual(testCase, rootA, rootB, "AbsTol", 0, ...
    "root selection must be deterministic");
correlation = abs(ifft(abs(fft(rootA)).^2)) / 63;
verifyLessThan(testCase, max(correlation(2:end)), 1, ...
    "autocorrelation sidelobes must stay below the main peak");
verifyEqual(testCase, correlation(1), 1, "AbsTol", 1e-12);
end

function testCodebookIsCyclicShiftsEq6_6(testCase)
root = scfde.equalizers.ch6_select_csk_root(63);
book = scfde.equalizers.ch6_csk_codebook(root, 4);
verifyEqual(testCase, size(book), [4, 63]);
for q = 0:3
    verifyEqual(testCase, book(q + 1, :), circshift(root, q), "AbsTol", 0);
end
end

function testDemodCorrelationPeakEq6_9(testCase)
% theta = (1/G) Re{ F^{-1}[(F s_hat)* .* (F alpha)] } with G = 63.  The
% (6-9) conjugate sits on the RECEIVED side, so a +shift transmission
% peaks at the NEGATIVE shift position; the estimated shift is mapped
% back as mod(-(peak-1), G).  (The book's (6-10) vs (6-11)/(6-12)
% direction is SOURCE-INCONSISTENT, recorded in the traceability; here
% the (6-9) conjugate direction is kept as written.)
root = scfde.equalizers.ch6_select_csk_root(63);
G = numel(root);
rng(1001, "twister");
shift = randi([0, 3], 1);
s = circshift(root, shift);
theta = (1 / G) * real(ifft(conj(fft(s)) .* fft(root)));
[peak, pos] = max(theta);
estimatedShift = mod(-(pos - 1), G);
verifyEqual(testCase, estimatedShift, shift, ...
    "(6-9) correlation must recover the transmitted shift via the negative-shift mapping");
verifyTrue(testCase, peak > max(theta([1:pos - 1, pos + 1:end])), ...
    "the peak must be strict");
end

function testDictionaryDecisionEqualsCorrelationUnderIdentity(testCase)
% Under an identity channel the dictionary rows are the codebook rows,
% so the nearest-dictionary decision equals the (6-9) correlation peak
% (mapped back through the negative-shift convention).
root = scfde.equalizers.ch6_select_csk_root(63);
book = scfde.equalizers.ch6_csk_codebook(root, 4);
rng(1002, "twister");
shift = randi([0, 3], 1);
s = circshift(root, shift) + sqrt(1e-6 / 2) * ...
    (randn(1, 63) + 1j * randn(1, 63));
[decision] = scfde.equalizers.ch6_hard_dictionary_detect(s, book);
theta = (1 / 63) * real(ifft(conj(fft(s)) .* fft(root)));
[~, pos] = max(theta);
expectedDecision = mod(-(pos - 1), 63) + 1;
verifyEqual(testCase, decision, expectedDecision);
end

function testWrapperIdentityExact(testCase)
% Identity circular channel + zero noise: the transmitter uses the SAME
% user-1 dictionary as the receiver (ch6_conventional_dictionaries
% applies the user shift); the wrapper recovers the indices exactly and
% outputs the BASE codebook chips (book(idx,:)), not the shifted
% dictionary chips.
codeLength = 63;
root = scfde.equalizers.ch6_select_csk_root(codeLength);
book = scfde.equalizers.ch6_csk_codebook(root, 4);
imp = [1, zeros(1, codeLength - 1)];
dicts = scfde.equalizers.ch6_conventional_dictionaries(book, imp, 1);
rng(1003, "twister");
symbols = 4;
idx = randi(4, 1, symbols);
chips = reshape(dicts{1}(idx, :).', 1, []);
ch = struct("received", chips, "impulse", imp, ...
    "branches", [chips; chips]);
src = struct("data", ones(1, symbols * codeLength), ...
    "tx", chips, "training", ones(1, 32));
cfg = struct("noiseVariance", 1e-9, "codeLength", codeLength, ...
    "cskOrder", 4, "conventionalUsers", 1, "snrDb", 99);
recv = scfde.equalizers.csk_matched_filter(ch, src, cfg);
det = recv.traces{1}.indices(:).';
verifyEqual(testCase, det, idx, ...
    "identity CSK frame must be recovered exactly");
expectedOutputs = reshape(book(idx, :).', 1, []);
verifyEqual(testCase, recv.outputs{1}, expectedOutputs, "AbsTol", 0);
end

function testMultiUserInputDimension(testCase)
root = scfde.equalizers.ch6_select_csk_root(63);
book = scfde.equalizers.ch6_csk_codebook(root, 4);
rng(1004, "twister");
received = zeros(3, 63);
for s = 1:3
    received(s, :) = book(randi(4), :);
end
dicts = {book, circshift(book, 1, 2)};
[decision, expected] = scfde.equalizers.ch6_matched_filter_detect(received, dicts);
verifyEqual(testCase, size(decision), [3, 2]);
verifyEqual(testCase, size(expected), [2, 3, 63]);
end

function testBitTableMapping(testCase)
[~, bits] = scfde.equalizers.ch6_csk_codebook( ...
    scfde.equalizers.ch6_select_csk_root(63), 4);
verifyEqual(testCase, size(bits), [4, 2]);
for q = 0:3
    verifyEqual(testCase, bits(q + 1, :), bitget(q, 1:2));
end
end

function testWrapperRngPreservedAndContracts(testCase)
codeLength = 63;
root = scfde.equalizers.ch6_select_csk_root(codeLength);
book = scfde.equalizers.ch6_csk_codebook(root, 4);
imp = [1, 0.4 * exp(1j * 0.3), 0.15 * exp(-1j * 0.6)];
dicts = scfde.equalizers.ch6_conventional_dictionaries(book, imp, 1);
rng(1005, "twister");
symbols = 4;
idx = randi(4, 1, symbols);
received = complex(zeros(symbols, codeLength));
for s = 1:symbols
    received(s, :) = dicts{1}(idx(s), :) + sqrt(1e-6 / 2) * ...
        (randn(1, codeLength) + 1j * randn(1, codeLength));
end
flat = reshape(received.', 1, []);
ch = struct("received", flat, "impulse", imp, "branches", [flat; flat]);
src = struct("data", ones(1, symbols * codeLength), ...
    "tx", flat, "training", ones(1, 32));
cfg = struct("noiseVariance", 1e-6, "codeLength", codeLength, ...
    "cskOrder", 4, "conventionalUsers", 1, "snrDb", 60);
before = rng;
recv = scfde.equalizers.csk_matched_filter(ch, src, cfg);
after = rng;
verifyEqual(testCase, after, before, ...
    "wrapper must preserve caller RNG state");
verifyEqual(testCase, recv.ids, "csk-matched-filter");
verifyEqual(testCase, recv.traces{1}.formulaStatus, "ALG-EQUIV");
verifyTrue(testCase, isfield(recv.traces{1}, "formulaMode"));
verifyTrue(testCase, isfield(recv.traces{1}, "bookExperimentEquivalent"));
verifyTrue(testCase, isfield(recv.traces{1}, "effectiveParameters"));
verifyEqual(testCase, numel(recv.traces{1}.indices), symbols);
verifyTrue(testCase, all(recv.traces{1}.indices >= 1 & ...
    recv.traces{1}.indices <= 4));
verifyEqual(testCase, numel(recv.outputs{1}), symbols * codeLength);
end
