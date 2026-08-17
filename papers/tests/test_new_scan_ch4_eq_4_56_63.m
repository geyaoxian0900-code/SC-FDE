function tests = test_new_scan_ch4_eq_4_56_63
%TEST_NEW_SCAN_CH4_EQ_4_56_63 Strict-formula tests recovered from the new
% high-resolution scan book/P90.png (2026-08-17):
%   * (4-56)~(4-58) FD-DFE/FD-Turbo coefficients: D_k, lambda, b_k, w_k
%     with the formula-derived zero-sum sum_k b_k = 0 (no projection);
%   * (4-55) rho = E[|x_bar|^2] hard-decision iteration flow;
%   * registered fd-dfe / fd-turbo bank contract (finite BER, 512 bits).
%
% Independent oracles only - no production helper reuse (except the
% trivial ch4_hard_bpsk sign function in the flow oracle).  The setup
% adds BOTH papers and papers/modules so clean matlab -batch runs do not
% depend on persistent paths.

tests = functiontests({ ...
    @testFdDfeWeightsEq4_56_58, ...
    @testFdDfeStrictFlowOnSmallFrame, ...
    @testFdDfeAndFdTurboBanksFinite});
%#ok<*DEFNU>  % setupOnce is invoked by the framework, not by name
%#ok<*NASGU>  % fixture outputs unused by individual tests are intentional
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(papersDir);
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testFdDfeWeightsEq4_56_58(testCase)
% (4-55)~(4-58) from book/P90.png:
%   D_k     = sigma^2 + |h_k|^2 - rho*|h_k|^2
%   lambda  = sigma^2 * sum_k(1/D_k) / sum_k((sigma^2+|h_k|^2)/D_k)
%   b_k     = [lambda*(sigma^2+|h_k|^2) - sigma^2] / D_k
%   w_k     = conj(h_k)*(1+b_k) / (sigma^2+|h_k|^2)
rng(2502, "twister");
N = 16;
H = (randn(1, N) + 1j * randn(1, N)) / sqrt(2);
rho = 0.6;
noiseVariance = 0.05;
A = noiseVariance + abs(H).^2;
D = A - rho * abs(H).^2;
lambdaExpected = noiseVariance * sum(1 ./ D) / sum(A ./ D);
bExpected = (lambdaExpected * A - noiseVariance) ./ D;
wExpected = conj(H) .* (1 + bExpected) ./ A;
[W, B, lam] = scfde.equalizers.ch4_fd_dfe_weights(H, rho, noiseVariance);
verifyEqual(testCase, lam, lambdaExpected, "AbsTol", 1e-12, "(4-58) lambda");
verifyEqual(testCase, B, bExpected, "AbsTol", 1e-12, "(4-57) b_k");
verifyEqual(testCase, W, wExpected, "AbsTol", 1e-12, "(4-56) w_k");
% Formula-derived zero sum (scale-aware): sum_k b_k = 0 follows from
% (4-58); it must NOT come from a B - mean(B) projection.
verifyTrue(testCase, abs(sum(B)) <= 1e-9 * max(sum(abs(B)), 1), ...
    "sum_k b_k = 0 must follow from (4-58)");
% Negatives:
% (a) swapped numerator terms must differ.
bSwap = (lambdaExpected * abs(H).^2 - noiseVariance) ./ D;
verifyTrue(testCase, any(abs(bSwap - bExpected) > 1e-9), ...
    "swapped numerator terms must be rejected by the oracle");
% (b) the generic MMSE baseline must differ from (4-56) w_k.
wMmse = conj(H) ./ A;
verifyTrue(testCase, any(abs(wMmse - W) > 1e-9), ...
    "the generic MMSE baseline must differ from the (4-56) w_k");
% (c) invalid inputs raise (D_k <= 0 and rho outside [0,1]).
verifyError(testCase, @() scfde.equalizers.ch4_fd_dfe_weights(H, 1, 0), ...
    "SCFDE:InvalidDfeWeights", "D_k <= 0 must be rejected");
verifyError(testCase, @() scfde.equalizers.ch4_fd_dfe_weights(H, 1.2, 0.1), ...
    "SCFDE:InvalidDfeWeights", "rho > 1 must be rejected");
end

function testFdDfeStrictFlowOnSmallFrame(testCase)
% Hard-decision iteration flow per (4-55): iteration 1 has zero feedback
% (rho = 0, previous = 0), iterations >= 2 use the hard BPSK decisions
% of the previous estimate with rho = mean(|previous|^2) = 1.
[frame, ~, tx] = buildMiniFrame(2501, 64, 32);
N = frame.frameLength;
imp = [1, 0.4 * exp(1j * 0.3)];
H = fft([imp, zeros(1, N - numel(imp))]);
noiseVariance = 1e-9;
Y = fft(ifft(H .* fft(tx)));            % noiseless deterministic frame
cfg = struct("iterations", 2, "baselineDecoder", "Log-MAP");
[~, ~, trace] = scfde.equalizers.ch4_iterate_fd_dfe( ...
    Y, H, noiseVariance, frame, cfg);
% iteration 1: rho = 0, previous = 0 -> estimate = ifft(W0 .* Y)
[W0, ~, lam0] = scfde.equalizers.ch4_fd_dfe_weights(H, 0, noiseVariance);
verifyEqual(testCase, trace.rhoHistory(1), 0, "AbsTol", 0);
verifyEqual(testCase, trace.lambdaHistory(1), lam0, "AbsTol", 1e-12);
verifyEqual(testCase, trace.frequencyWeights(1, :), W0, "AbsTol", 1e-12);
verifyEqual(testCase, trace.softEstimates(1, :), ifft(W0 .* Y), ...
    "AbsTol", 1e-10, "iteration 1 must have zero feedback");
% iteration 2: previous = hard decisions of iteration 1, rho = 1
hard1 = scfde.equalizers.ch4_hard_bpsk(trace.softEstimates(1, :));
[W1, B1, lam1] = scfde.equalizers.ch4_fd_dfe_weights(H, 1, noiseVariance);
verifyEqual(testCase, trace.rhoHistory(2), 1, "AbsTol", 0);
verifyEqual(testCase, trace.lambdaHistory(2), lam1, "AbsTol", 1e-12);
verifyEqual(testCase, trace.softEstimates(2, :), ...
    ifft(W1 .* Y - B1 .* fft(hard1)), "AbsTol", 1e-10, ...
    "iteration 2 must use the hard decisions of iteration 1");
end

function testFdDfeAndFdTurboBanksFinite(testCase)
% Registered wrappers: finite BER and exactly 512 information bits.
res = run_unified_equalizer(struct("equalizers", ["fd-dfe", "fd-turbo"], ...
    "scenario", "turbo", "frameCount", 1, "snrDb", 18, ...
    "makePlot", false, "randomSeed", 42));
verifyEqual(testCase, numel(res.ids), 2);
verifyTrue(testCase, all(isfinite(res.ber)), ...
    "fd-dfe and fd-turbo BER must be finite at 18 dB");
verifyEqual(testCase, res.totalBits, [512, 512], ...
    "both wrappers must return exactly 512 information bits");
end

function [frame, information, tx] = buildMiniFrame(seed, trainingLength, infoLength)
% Deterministic mini turbo frame (noiseless construction by the caller).
rng(seed, "twister");
information = randi([0 1], 1, infoLength);
coded = scfde.equalizers.ch4_convolutional_encode(information);
permutation = randperm(2 * infoLength);
training = 1 - 2 * randi([0 1], 1, trainingLength);
tx = [training, 1 - 2 * coded(permutation)];
frameLength = numel(tx);
frame = struct("frameLength", frameLength, ...
    "trainingLength", trainingLength, ...
    "codedLength", 2 * infoLength, ...
    "informationLength", infoLength, ...
    "trainingIndices", 1:trainingLength, ...
    "dataIndices", trainingLength + (1:2 * infoLength), ...
    "trainingSymbols", training, ...
    "informationSymbols", 1 - 2 * information, ...
    "informationBits", double(information), ...
    "permutation", permutation, ...
    "inversePermutation", zeros(1, 2 * infoLength));
frame.inversePermutation(permutation) = 1:2 * infoLength;
end
