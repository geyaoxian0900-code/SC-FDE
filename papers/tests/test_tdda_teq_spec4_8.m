function tests = test_tdda_teq_spec4_8
%TEST_TDDA_TEQ_SPEC4_8 Batch-11 deterministic audit of tdda-teq (spec 4.8
% boxed unnormalized LMS DFE).  The observed 18 dB BER ~ 0.51 was traced
% by theory to the step size: cfg.tdNlmsStep = 0.35 is an NLMS-era value
% that EXCEEDS the joint-regressor MEAN-convergence reference and
% diverges.  The production now uses cfg.tddaMu (default 0.05, about
% HALF the measured reference on the unit-energy 16-tap turbo input at
% 18 dB) and reports trace.meanConvergenceBound /
% trace.withinMeanConvergenceBound - a THEORETICAL DIAGNOSTIC, NOT a
% stability guarantee (a step below the reference can still diverge in
% this decision-feedback system; observed).
%
% Boundary conventions under test (recorded in the trace):
%   * causal input window r_n zero-padded at the frame head (frame-tail
%     coded data must never leak into the frame-head training);
%   * first round has NO data prior (no true-channel MMSE initialization,
%     iteration 1 adapts on the training segment only).
%
% Independent, deterministic oracles (no production helper reuse):
%   * unit/two-tap channel noiseless: exact 512 decision recovery,
%     training-end weights nonzero, training error converges (relative
%     drop + no round-to-round worsening, NO unsourced absolute
%     threshold), finite weights, exact noiseless decisions;
%   * mean-convergence reference: 2/lambda_max(R_hat),
%     u_n = [r_n; -x_bar_{n-1}], reproduced inline per round; the
%     over-reference step is chosen DYNAMICALLY (1.1x the recorded
%     reference) and must be FLAGGED, while actual divergence is judged
%     from the error/weight TRAJECTORIES;
%   * negative RED: flipping only the LAST coded symbol of a linear-
%     convolution frame must leave the first feedforwardTaps samples'
%     iteration-1 estimates bit-identical (no circular wrap);
%   * longer training (synthetic frames) must not degrade the noiseless
%     recovery;
%   * same seed exact reproducibility, different seed variation.

tests = functiontests({ ...
    @testUnitChannelNoiselessExactDecisions, ...
    @testTwoTapNoiselessExactDecisions, ...
    @testTrainingWeightsNonzeroAndErrorConverges, ...
    @testMeanConvergenceBoundAndDivergenceDetection, ...
    @testFrameTailDoesNotLeakIntoHeadTraining, ...
    @testLongerTrainingNotWorse, ...
    @testSeedReproducibilityAndVariation});
%#ok<*DEFNU>  % setupOnce is invoked by the framework, not by name
%#ok<*NASGU>  % fixture outputs unused by individual tests are intentional
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function [channel, source, cfg] = buildTddaFixture(seed, impulse, snrDb, iterations)
rng(seed, "twister");
information = randi([0 1], 1, 512);
coded = scfde.equalizers.ch4_convolutional_encode(information);
permutation = randperm(1024);
training = 1 - 2 * randi([0 1], 1, 256);
tx = [training, 1 - 2 * coded(permutation)];
H = fft([impulse, zeros(1, numel(tx) - numel(impulse))]);
noiseVariance = 10^(-snrDb / 10);
received = ifft(H .* fft(tx)) + sqrt(noiseVariance / 2) * ...
    (randn(size(tx)) + 1j * randn(size(tx)));
channel = struct("received", received, "impulse", impulse, ...
    "branches", [received; received]);
source = struct("training", training, "data", 1 - 2 * information, ...
    "tx", tx);
cfg = struct("noiseVariance", noiseVariance, "iterations", iterations, ...
    "trainingSymbols", 256, "infoBits", 512, ...
    "permutation", permutation, "turboDecoderMode", "Log-MAP", ...
    "baselineDecoder", "Log-MAP", "tdAdaptiveTaps", 16, ...
    "feedbackTaps", 6, "snrDb", snrDb);
end

function [frame, information, tx] = buildSyntheticFrame(seed, trainingLength, infoLength, impulse) %#ok<INUSD>
% Linear-convolution synthetic frame (noise-free, zero channel state):
% used by the boundary-rule tests where the frame-tail isolation matters.
% The impulse argument documents the channel the caller convolves with.
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

function cfg = buildCoreCfg(trainingLength, infoLength, permutation)
cfg = struct("noiseVariance", 1e-9, "iterations", 1, ...
    "trainingSymbols", trainingLength, "infoBits", infoLength, ...
    "permutation", permutation, "turboDecoderMode", "Log-MAP", ...
    "tdAdaptiveTaps", 16, "feedbackTaps", 6, "tddaMu", 0.05);
end

function testUnitChannelNoiselessExactDecisions(testCase)
% Unit channel, noiseless: the boxed LMS DFE must recover all 512
% information decisions exactly and stay aligned with source.data.
[channel, source, cfg] = buildTddaFixture(1101, [1, 0, 0], 99, 2);
cfg.noiseVariance = 1e-9;
recv = scfde.equalizers.tdda_teq(channel, source, cfg);
verifyEqual(testCase, recv.outputs{1}, source.data, ...
    "unit-channel noiseless decisions must be exact and aligned");
verifyTrue(testCase, all(recv.traces{1}.withinMeanConvergenceBound), ...
    "the default step must be below the mean-convergence reference every round (diagnostic only)");
verifyEqual(testCase, recv.traces{1}.meanBoundSatisfiedAllIterations, true, ...
    "the overall diagnostic must use the minimum reference across rounds");
end

function testTwoTapNoiselessExactDecisions(testCase)
% Short two-tap channel, noiseless: exact recovery.
[channel, source, cfg] = buildTddaFixture(1102, [1, 0.4], 99, 2);
cfg.noiseVariance = 1e-9;
recv = scfde.equalizers.tdda_teq(channel, source, cfg);
verifyEqual(testCase, recv.outputs{1}, source.data, ...
    "two-tap noiseless decisions must be exact");
end

function testTrainingWeightsNonzeroAndErrorConverges(testCase)
% Training-segment audit WITHOUT an unsourced absolute error threshold:
% the training error must drop substantially from round 1, must not
% worsen between rounds, the final weights must be finite and nonzero,
% and the noiseless decisions must be exact.  (iterations=3 is an
% explicit engineering parameter and is recorded in the trace via
% effectiveParameters.)
[channel, source, cfg] = buildTddaFixture(1103, [1, 0.4], 99, 3);
cfg.noiseVariance = 1e-9;
recv = scfde.equalizers.tdda_teq(channel, source, cfg);
trace = recv.traces{1};
weights = ifft(trace.finalChannel);
verifyTrue(testCase, all(isfinite(weights)), ...
    "final weights must be finite");
verifyTrue(testCase, norm(weights) > 1e-6, ...
    "training must produce nonzero final weights");
verifyTrue(testCase, trace.trainingErrorPower(end) < ...
    trace.trainingErrorPower(1) / 10, ...
    "training error must drop substantially from the first round");
verifyTrue(testCase, all(diff(trace.trainingErrorPower) <= 1e-12), ...
    "training error must not worsen between rounds");
verifyEqual(testCase, recv.outputs{1}, source.data, ...
    "noiseless decisions must be exact (trajectory-level check)");
end

function testMeanConvergenceBoundAndDivergenceDetection(testCase)
% The joint-regressor MEAN-convergence reference 2/lambda_max(R_hat),
% u_n = [r_n; -x_bar_{n-1}], must be reproduced per round in the trace
% (independence-based approximation; a THEORETICAL DIAGNOSTIC that is
% NOT a stability guarantee - a step below it can still diverge in this
% decision-feedback system).  The feedforward-only estimate
% 2/(Nf*mean|r|^2) is also reported.  The over-reference step is chosen
% DYNAMICALLY from the recorded reference (1.1x, since a fixed 0.5 sits
% below the measured reference here) and must be FLAGGED; actual
% divergence is judged from the error/weight TRAJECTORIES.  Round-1's
% reference is exactly reproducible inline (no-prior soft symbols).
[channel, source, cfg] = buildTddaFixture(1104, [1, 0.4], 10, 1);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
cfg.tddaMu = 0.05;
[~, ~, traceStable] = scfde.equalizers.ch4_iterate_td_nlms_turbo( ...
    channel.received, [], [], [], cfg.noiseVariance, frame, cfg);
N = numel(channel.received);
Nf = min(cfg.tdAdaptiveTaps, N);
fb = min(cfg.feedbackTaps, N - 1);
xbar = zeros(1, N);
xbar(frame.trainingIndices) = frame.trainingSymbols;
acc = complex(zeros(Nf + fb));
for n = 1:N
    if n >= Nf
        r = channel.received(n:-1:n - Nf + 1).';
    else
        r = [channel.received(n:-1:1).'; complex(zeros(Nf - n, 1))];
    end
    xb = complex(zeros(fb, 1));
    if n > 1
        c = min(fb, n - 1);
        xb(1:c) = xbar(n - 1:-1:n - c).';
    end
    u = [r; -xb];
    acc = acc + u * u';
end
covariance = (acc + acc') / 2 / N;      % Hermitian cleanup (same as production)
expectedJoint = 2 / max(max(real(eig(covariance))), eps);
expectedFfOnly = 2 / (Nf * mean(abs(channel.received).^2));
verifyEqual(testCase, traceStable.meanConvergenceBound(1), expectedJoint, ...
    "AbsTol", 1e-12);
verifyEqual(testCase, traceStable.feedforwardOnlyMeanBound, expectedFfOnly, ...
    "AbsTol", 1e-12);
verifyTrue(testCase, all(isfinite(traceStable.meanConvergenceBound)), ...
    "the per-round reference must be recorded for every round");
verifyTrue(testCase, all(traceStable.withinMeanConvergenceBound));
verifyEqual(testCase, traceStable.minimumMeanConvergenceBound, ...
    min(traceStable.meanConvergenceBound), "AbsTol", 0);
verifyEqual(testCase, traceStable.meanBoundSatisfiedAllIterations, true);
stableWeights = ifft(traceStable.finalChannel);
verifyTrue(testCase, all(isfinite(stableWeights)), ...
    "the conservative step must keep the weights finite (trajectory check)");
% Over-reference step chosen DYNAMICALLY from the recorded reference:
% a fixed mu=0.5 sits BELOW the measured reference on this fixture and
% still diverges - exactly why this quantity is a diagnostic, not a
% stability guarantee.
muOver = 1.1 * traceStable.meanConvergenceBound(1);
cfg.tddaMu = muOver;
[~, ~, traceUnstable] = scfde.equalizers.ch4_iterate_td_nlms_turbo( ...
    channel.received, [], [], [], cfg.noiseVariance, frame, cfg);
verifyTrue(testCase, traceUnstable.withinMeanConvergenceBound(1) == false, ...
    "the over-reference step must be FLAGGED by the diagnostic");
verifyTrue(testCase, traceUnstable.meanBoundSatisfiedAllIterations == false, ...
    "the minimum-reference overall diagnostic must flag the over-reference step");
stableNorm = norm(stableWeights);
unstableNorm = norm(ifft(traceUnstable.finalChannel));
verifyTrue(testCase, ~isfinite(unstableNorm) || ...
    unstableNorm > 1e3 * stableNorm, ...
    "an over-reference step must blow the weights up on a noisy input");
stableTrainingError = traceStable.trainingErrorPower(1);
unstableTrainingError = traceUnstable.trainingErrorPower(1);
verifyTrue(testCase, ~isfinite(unstableTrainingError) || ...
    unstableTrainingError > 100 * max(stableTrainingError, eps), ...
    "divergence must also be visible in the training-error trajectory");
end

function testFrameTailDoesNotLeakIntoHeadTraining(testCase)
% Negative RED test for the input-window boundary rule: the causal
% window is zero-padded at the frame head, so frame-tail coded data can
% never leak into the frame-head training regressors.  On a LINEAR-
% convolution fixture flipping only the LAST coded symbol leaves the
% frame head untouched, so the first feedforwardTaps samples'
% iteration-1 estimates must be bit-identical (the previous circular
% mod() window made them differ).
[frame, ~, txA] = buildSyntheticFrame(1110, 256, 512, [1, 0.4, -0.2]);
txB = txA;
txB(end) = -txB(end);          % flip only the last (coded) symbol
receivedA = filter([1, 0.4, -0.2], 1, txA);   % linear convolution
receivedB = filter([1, 0.4, -0.2], 1, txB);
verifyTrue(testCase, all(receivedA(1:16) == receivedB(1:16)), ...
    "premise: linear channel keeps the frame head identical");
cfg = buildCoreCfg(256, 512, frame.permutation);
[~, ~, traceA] = scfde.equalizers.ch4_iterate_td_nlms_turbo( ...
    receivedA, [], [], [], 1e-9, frame, cfg);
[~, ~, traceB] = scfde.equalizers.ch4_iterate_td_nlms_turbo( ...
    receivedB, [], [], [], 1e-9, frame, cfg);
verifyEqual(testCase, traceA.softEstimates(1, 1:16), ...
    traceB.softEstimates(1, 1:16), "AbsTol", 0, ...
    "frame-tail coded data must not leak into frame-head regressors");
end

function testLongerTrainingNotWorse(testCase)
% Synthetic frames with 256 vs 400 training symbols: the noiseless
% recovery must not degrade when the training length grows.
for trainingLength = [256, 400]
    infoLength = 512;
    [frame, information, tx] = buildSyntheticFrame(1105, ...
        trainingLength, infoLength, [1, 0.4]);
    received = filter([1, 0.4], 1, tx);
    cfg = buildCoreCfg(trainingLength, infoLength, frame.permutation);
    [bits] = scfde.equalizers.ch4_iterate_td_nlms_turbo( ...
        received, [], [], [], 1e-9, frame, cfg);
    verifyEqual(testCase, double(bits), double(information), ...
        sprintf("training %d: noiseless decisions must be exact", ...
        trainingLength));
end
end

function testSeedReproducibilityAndVariation(testCase)
% Same seed reproduces exactly; a different seed changes the output on
% a noisy frame.
[chA, srcA, cfgA] = buildTddaFixture(1106, [1, 0.4], 10, 2);
[chB, srcB, cfgB] = buildTddaFixture(1106, [1, 0.4], 10, 2);
[chC, srcC, cfgC] = buildTddaFixture(1107, [1, 0.4], 10, 2);
rA = scfde.equalizers.tdda_teq(chA, srcA, cfgA);
rB = scfde.equalizers.tdda_teq(chB, srcB, cfgB);
rC = scfde.equalizers.tdda_teq(chC, srcC, cfgC);
verifyEqual(testCase, rA.outputs{1}, rB.outputs{1}, ...
    "same seed must reproduce exactly");
verifyTrue(testCase, any(rA.outputs{1} ~= rC.outputs{1}), ...
    "a different seed must change the noisy-frame output");
end
