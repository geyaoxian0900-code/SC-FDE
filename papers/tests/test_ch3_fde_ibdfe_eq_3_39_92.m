function tests = test_ch3_fde_ibdfe_eq_3_39_92
%TEST_CH3_FDE_IBDFE_EQ_3_39_92 Strict-formula tests for the remaining six
% Chapter-3 methods (spec 3.1/3.2/3.4~3.7, book (3-39)~(3-92)):
% mmse-fde, zf-fde, sd-ibdfe, hd-ibdfe, ice-sd-ibdfe, ice-hd-ibdfe.
%
% Independent oracles (no production helper reuse):
%   * mmse: per-bin H*/(|H|^2+sigma^2) equals the book form
%     H*/(N sigma^2 + M_X |H|^2) up to the common real factor N
%     (m_x = 1, M_X = N) - the golden decision-equivalence proof the
%     spec demands; iteration-1 IBDFE degrades to the MMSE decisions;
%   * zf: strict 1/(lambda H_k), no epsilon floor; exact-null fixture
%     must REPORT singularBins (RED against the old max(H,eps) floor);
%   * ibdfe structure: B = C H - 1, unit gain, hard feedback = previous
%     complete block's sliced decisions, soft feedback = QPSK posterior
%     mean (tanh form = 4-point softmax, never hard-sliced);
%   * ice: (3-88)~(3-92) LS -> DFT truncation -> boxed MMSE variance mix
%     from iteration 2 (first round keeps the training-based H); RED
%     against the removed fixed-rho LS.

tests = functiontests({ ...
    @testMmseGoldenCommonFactorEq3_71, ...
    @testFirstIbdfeIterationDegradesToMmse, ...
    @testZfStrictFormAndSingularReporting, ...
    @testIbdfeStructureEq3_64_71, ...
    @testHardFeedbackUsesPreviousCompleteBlock, ...
    @testSoftFeedbackPosteriorMeanNoHardSlice, ...
    @testIceChannelUpdateEq3_88_92, ...
    @testCh3WrappersRngPreservedAndStatus});
%#ok<*DEFNU>  % setupOnce is invoked by the framework, not by name
%#ok<*NASGU>  % fixture outputs unused by individual tests are intentional
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function [received, block, H, h, nv] = buildCh3Frame(testCase, seed, snrDb)
N = 64;
rng(seed, "twister");
data = ((2 * randi([0, 1], 1, 40) - 1) + ...
    1j * (2 * randi([0, 1], 1, 40) - 1)) / sqrt(2);
uw = scfde.equalizers.ch3_zadoff_chu(24, 1);
block = [data, uw];
h = [1, 0.7 * exp(1j * 0.5), 0.3 * exp(-1j * 0.8)];
nv = 10^(-snrDb / 10);
received = ifft(fft([h, zeros(1, N - numel(h))]) .* fft(block)) + ...
    sqrt(nv / 2) * (randn(1, N) + 1j * randn(1, N));
H = fft([h, zeros(1, N - numel(h))]);
end

function testMmseGoldenCommonFactorEq3_71(testCase)
% The production per-bin filter H*/(|H|^2+sigma^2) must equal the book
% form H*/(N sigma^2 + M_X |H|^2) up to the common REAL factor N with
% m_x = 1 (unit-energy symbols), M_X = N*m_x - the golden proof that the
% omitted common factor is decision-equivalent (spec 3.1).
rng(701, "twister");
N = 64;
h = [1, 0.6 * exp(1j * 0.4), 0.25 * exp(-1j * 0.7)];
H = fft([h, zeros(1, N - numel(h))]);
Y = fft(randn(1, N) + 1j * randn(1, N));
nv = 10^(-15 / 10);
X = scfde.equalizers.ch3_mmse_frequency_equalize(Y, H, nv);
prodC = conj(H) ./ (abs(H).^2 + nv);
bookC = conj(H) ./ (N * nv + N * 1 * abs(H).^2);
verifyEqual(testCase, X, Y .* prodC, "AbsTol", 1e-13);
verifyEqual(testCase, prodC, N * bookC, "AbsTol", 1e-12);
verifyTrue(testCase, all(imag(prodC ./ bookC) < 1e-12), ...
    "the common factor must be REAL (decision-equivalent)");
end

function testFirstIbdfeIterationDegradesToMmse(testCase)
[received, block, H, h, nv] = buildCh3Frame(testCase, 702, 15);
ch = struct("received", received, "impulse", h);
src = struct("data", block(1:40), "tx", block, "training", block(1:40));
cfgMmse = struct("noiseVariance", nv, "snrDb", 15, "modulation", "qpsk");
cfgOne = cfgMmse;
cfgOne.ibdfeIterations = 1;
recvMmse = scfde.equalizers.mmse_fde(ch, src, cfgMmse);
recvSd1 = scfde.equalizers.sd_ibdfe(ch, src, cfgOne);
verifyEqual(testCase, recvSd1.outputs{1}, recvMmse.outputs{1}, ...
    "iteration-1 SD-IBDFE must degrade to the MMSE-FDE decisions");
end

function testZfStrictFormAndSingularReporting(testCase)
% Strict (3-43)/(3-44): C_k = 1/(lambda H_k) with NO epsilon floor;
% lambda = 1 in the zero-Doppler scenario.
[received, block, H, h, nv] = buildCh3Frame(testCase, 703, 20);
ch = struct("received", received, "impulse", h);
src = struct("data", block(1:40), "tx", block, "training", block(1:40));
cfg = struct("noiseVariance", nv, "snrDb", 20, "modulation", "qpsk");
recv = scfde.equalizers.zf_fde(ch, src, cfg);
symbolsOracle = ifft(fft(received) ./ H);
verifyEqual(testCase, recv.estimates{1}, symbolsOracle(1:40), "AbsTol", 1e-12);
verifyEqual(testCase, recv.traces{1}.lambda, 1);
verifyEqual(testCase, recv.traces{1}.singularBins, zeros(1, 0));
verifyEqual(testCase, recv.traces{1}.formulaStatus, "BOOK-EXACT");
% Exact-null fixture: strict ZF does not exist at H_k = 0; the wrapper
% must REPORT the singular bins instead of flooring with eps (RED
% against the old max(H,eps) path, which silently returned 1/eps).
N = 64;
hNull = [1, 1] / sqrt(2);
receivedNull = ifft(fft([hNull, zeros(1, N - 2)]) .* fft(block));
chNull = struct("received", receivedNull, "impulse", hNull);
recvNull = scfde.equalizers.zf_fde(chNull, src, cfg);
verifyEqual(testCase, recvNull.traces{1}.singularBins, N / 2 + 1);
verifyTrue(testCase, any(~isfinite(recvNull.estimates{1})), ...
    "strict ZF at an exact null must be non-finite (reported), not floored");
end

function testIbdfeStructureEq3_64_71(testCase)
[received, block, H, h, nv] = buildCh3Frame(testCase, 704, 15);
N = 64;
uw = scfde.equalizers.ch3_zadoff_chu(24, 1);
training = scfde.equalizers.ch3_zadoff_chu(N, 1);
cfg = struct("fftSize", N, "dataSymbols", 40, "uwLength", 24, ...
    "ibdfeIterations", 3, "channelEstimateLength", 8, ...
    "channelRegularization", 0.1, "noiseVariance", nv, ...
    "modulation", "qpsk", "snrDb", 15);
[~, trace] = scfde.equalizers.ch3_ibdfe_equalize( ...
    received, received, training, H, nv, uw, cfg, "hard", false);
for iteration = 1:cfg.ibdfeIterations
    verifyEqual(testCase, trace.feedback(iteration, :), ...
        trace.feedforward(iteration, :) .* H - 1, "AbsTol", 1e-12);
    verifyEqual(testCase, trace.normalization(iteration), 1, "AbsTol", 1e-12);
end
verifyEqual(testCase, trace.formulaStatus, "BLOCKED-SOURCE-REVIEW", ...
    "weakest link ((3-86) A_k) keeps the plain IBDFE from BOOK-EXACT");
end

function testHardFeedbackUsesPreviousCompleteBlock(testCase)
% (3-64): X_tilde^(i-1) = Q{F^{-1} X_hat^(i-1)} - the hard feedback of
% iteration 2 must equal the SLICED DECISIONS of the iteration-1 run
% (with the UW tail), i.e. the previous complete block.
[received, block, H, h, nv] = buildCh3Frame(testCase, 705, 15);
N = 64;
uw = scfde.equalizers.ch3_zadoff_chu(24, 1);
training = scfde.equalizers.ch3_zadoff_chu(N, 1);
baseCfg = struct("fftSize", N, "dataSymbols", 40, "uwLength", 24, ...
    "ibdfeIterations", 1, "channelEstimateLength", 8, ...
    "channelRegularization", 0.1, "noiseVariance", nv, ...
    "modulation", "qpsk", "snrDb", 15);
[symbols1] = scfde.equalizers.ch3_ibdfe_equalize( ...
    received, received, training, H, nv, uw, baseCfg, "hard", false);
hard1 = (sign(real(symbols1)) + 1j * sign(imag(symbols1))) / sqrt(2);
hard1(41:end) = uw;
baseCfg.ibdfeIterations = 2;
[~, trace2] = scfde.equalizers.ch3_ibdfe_equalize( ...
    received, received, training, H, nv, uw, baseCfg, "hard", false);
verifyEqual(testCase, trace2.feedbackMeans(1, :), hard1, "AbsTol", 1e-12, ...
    "hard feedback must be the previous complete block's sliced decisions");
end

function testSoftFeedbackPosteriorMeanNoHardSlice(testCase)
% (3-84)/(3-85): X_bar = E[x | L_a] = sum_s s P(x=s|L_a).  The QPSK
% posterior mean is the tanh closed form of the 4-point softmax, and
% the soft path must NOT hard-slice (RED against a slicing soft path).
[received, block, H, h, nv] = buildCh3Frame(testCase, 706, 15);
N = 64;
uw = scfde.equalizers.ch3_zadoff_chu(24, 1);
training = scfde.equalizers.ch3_zadoff_chu(N, 1);
baseCfg = struct("fftSize", N, "dataSymbols", 40, "uwLength", 24, ...
    "ibdfeIterations", 1, "channelEstimateLength", 8, ...
    "channelRegularization", 0.1, "noiseVariance", nv, ...
    "modulation", "qpsk", "snrDb", 15);
[symbols1] = scfde.equalizers.ch3_ibdfe_equalize( ...
    received, received, training, H, nv, uw, baseCfg, "soft", false);
hardInline = (sign(real(symbols1)) + 1j * sign(imag(symbols1))) / sqrt(2);
decisionVariance = mean(abs(symbols1 - hardInline).^2);
sigmaEff = max(nv, decisionVariance);
tanhForm = (tanh(sqrt(2) * real(symbols1) / sigmaEff) + ...
    1j * tanh(sqrt(2) * imag(symbols1) / sigmaEff)) / sqrt(2);
% Independent 4-point posterior mean over the COMPLEX QPSK alphabet
% (the previous real-coordinate oracle subtracted a complex symbol from
% a real 4x2 matrix and was invalid).
constellation = [1 + 1j, 1 - 1j, -1 + 1j, -1 - 1j] / sqrt(2);
mean4 = complex(zeros(1, N));
for k = 1:N
    metric = abs(constellation - symbols1(k)).^2;
    w = exp(-metric / sigmaEff);
    w = w / sum(w);
    mean4(k) = sum(w .* constellation);
end
verifyEqual(testCase, tanhForm, mean4, "AbsTol", 1e-10);
mean1 = tanhForm;
mean1(41:end) = uw;
baseCfg.ibdfeIterations = 2;
[~, trace2] = scfde.equalizers.ch3_ibdfe_equalize( ...
    received, received, training, H, nv, uw, baseCfg, "soft", false);
verifyEqual(testCase, trace2.feedbackMeans(1, :), mean1, "AbsTol", 1e-12);
verifyTrue(testCase, any(abs(trace2.feedbackMeans(1, 1:40) - ...
    hardInline(1:40)) > 1e-9), ...
    "soft feedback must be the posterior mean, not hard-sliced chips");
end

function testIceChannelUpdateEq3_88_92(testCase)
% (3-88)~(3-92): LS from the current soft estimates, DFT truncation,
% boxed MMSE variance-weighted mix from iteration 2; the first round
% keeps the training-based H (RED against the removed fixed-rho LS).
[received, block, H, h, nv] = buildCh3Frame(testCase, 707, 15);
N = 64;
uw = scfde.equalizers.ch3_zadoff_chu(24, 1);
training = scfde.equalizers.ch3_zadoff_chu(N, 1);
H0 = H .* (1 + 0.05j);      % perturbed initial estimate
cfg = struct("fftSize", N, "dataSymbols", 40, "uwLength", 24, ...
    "ibdfeIterations", 3, "channelEstimateLength", 8, ...
    "channelRegularization", 0.1, "noiseVariance", nv, ...
    "modulation", "qpsk", "snrDb", 15);
[~, trace, HEnd] = scfde.equalizers.ch3_ibdfe_equalize( ...
    received, [], training, H0, nv, uw, cfg, "soft", true);
verifyEqual(testCase, trace.channelHistory(1, :), H0, "AbsTol", 0, ...
    "first round must keep the training-based H (no data update)");
Y = fft(received);
% The iteration-2 channel update uses the CURRENT round's soft
% estimates (trace.feedbackMeans(2,:)), per the production semantics:
%   H_LS^2 = R ./ X_D^0 = Y .* conj(X_bar^2) ./ |X_bar^2|^2
%   h_est = IFFT(H_LS), DFT truncation to channelEstimateLength taps,
%   H^2 = (sigmaDft2 * H_old + sigmaOld2 * H_DFT) / (sigmaDft2 + sigmaOld2)
% with sigmaDft2 = mean|H_LS - H_DFT|^2, sigmaOld2 = mean|H_old - H_LS|^2
% (scan-confirmed numerator order; variance definitions ENGINEERING).
softSpectrum = fft(trace.feedbackMeans(2, :));
hLs = Y .* conj(softSpectrum) ./ max(abs(softSpectrum).^2, eps);
hEst = ifft(hLs);
hDft = hEst;
hDft(cfg.channelEstimateLength + 1:end) = 0;
hDftSpectrum = fft(hDft);
sigmaDft2 = mean(abs(hLs - hDftSpectrum).^2);
sigmaOld2 = mean(abs(H0 - hLs).^2);
H2Oracle = (H0 .* sigmaDft2 + hDftSpectrum .* sigmaOld2) ./ ...
    max(sigmaOld2 + sigmaDft2, eps);
verifyEqual(testCase, trace.channelHistory(2, :), H2Oracle, "AbsTol", 1e-9);
verifyEqual(testCase, HEnd, trace.channelHistory(end, :), "AbsTol", 0);
verifyEqual(testCase, trace.channelUpdateStatus, "ENGINEERING-BLOCKED");
end

function testCh3WrappersRngPreservedAndStatus(testCase)
% mmse/zf/sd/hd/ice-sd/ice-hd: RNG transparency (the ice wrappers no
% longer synthesize noisy training observations), formula status in the
% trace, finite outputs.
[received, block, ~, h, nv] = buildCh3Frame(testCase, 708, 15);
ch = struct("received", received, "impulse", h);
src = struct("data", block(1:40), "tx", block, "training", block(1:40));
cfg = struct("noiseVariance", nv, "snrDb", 15, "modulation", "qpsk", ...
    "ibdfeIterations", 3);
registry = scfde.equalizer_registry();
targets = ["mmse-fde", "zf-fde", "sd-ibdfe", "hd-ibdfe", ...
    "ice-sd-ibdfe", "ice-hd-ibdfe"];
ch3 = find(ismember(registry.id, targets));
verifyEqual(testCase, numel(ch3), 6);
for m = ch3(:)'
    before = rng;
    recv = registry.module{m}(ch, src, cfg);
    after = rng;
    verifyEqual(testCase, after, before, ...
        "wrapper " + registry.id(m) + " must preserve caller RNG state");
    verifyTrue(testCase, isfield(recv.traces{1}, "formulaStatus"), ...
        "wrapper " + registry.id(m) + " must record formulaStatus");
    verifyTrue(testCase, all(isfinite(recv.outputs{1})), ...
        "wrapper " + registry.id(m) + " outputs must be finite");
    verifyEqual(testCase, recv.ids, registry.id(m));
end
end
