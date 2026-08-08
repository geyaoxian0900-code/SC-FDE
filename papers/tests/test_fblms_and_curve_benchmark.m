function tests = test_fblms_and_curve_benchmark
%TEST_FBLMS_AND_CURVE_BENCHMARK Tests for the strict overlap-save FBLMS
% equalizer (book Fig. 4-25) and the curve benchmark framework.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(papersDir); % run_unified_equalizer and other root entry points
addpath(fullfile(papersDir, "modules"));
addpath(fullfile(papersDir, "common"));
addpath(fullfile(papersDir, "engineering_simulation"));
addpath(fullfile(papersDir, "examples"));
testCase.TestData.papersDir = papersDir;
end

function testFblmsMatchesLinearConvolutionNoiseless(testCase)
% With a unit-impulse channel and zero noise, the FBLMS output must
% equal the reference signal after convergence - i.e. the overlap-save
% implementation produces a linear convolution and tracks the training
% reference, with the first Nf contaminated samples of the first block
% dropped.
N = 64;         % block length
Nf = 8;         % filter length
trainLength = 640;
signal = randi([0 1], 1, 1024) * 2 - 1;
step = 0.5;
epsilon = 1e-6;
[output, ~, trace] = scfde.equalizers.fblms_equalizer(signal, signal, ...
    trainLength, Nf, N, step, epsilon, false);
% The error power must converge toward zero.
verifyLessThan(testCase, trace.errorPower(end), 1e-2, ...
    "FBLMS must converge on the noiseless training reference");
% Converged output must track the reference within the soft-decision
% magnitude (sign-correct, small gain error).
startIdx = Nf + 6 * N + 1;
seg = output(startIdx:end);
refseg = signal(startIdx:startIdx + numel(seg) - 1);
mse = mean((seg - refseg).^2);
verifyLessThan(testCase, mse, 0.05, ...
    "converged noiseless FBLMS must track the reference");
% Symbol decisions must be exact.
verifyEqual(testCase, sign(seg), sign(refseg), ...
    "converged FBLMS decisions must match the reference symbols");
end

function testFblmsQpskDecisionDirected(testCase)
% The decision-directed branch must use a modulation-matched slicer:
% with a QPSK reference and the 4-quadrant unit-energy slicer, the
% converged equalizer must track the complex QPSK symbols (not collapse
% them to real BPSK).
N = 64;
Nf = 8;
trainLength = 640;
bits = randi([0 1], 1, 2048);
bitMatrix = reshape(bits, 2, []);
signal = ((1 - 2 * bitMatrix(1, :)) + ...
    1j * (1 - 2 * bitMatrix(2, :))) / sqrt(2);
signal = repmat(signal, 1, 4); % 1024 symbols
step = 0.5;
epsilon = 1e-6;
qpskSlicer = @(values) ((1 - 2 * (real(values) < 0)) + ...
    1j * (1 - 2 * (imag(values) < 0))) / sqrt(2);
[output, ~, trace] = scfde.equalizers.fblms_equalizer(signal, signal, ...
    trainLength, Nf, N, step, epsilon, true, qpskSlicer);
verifyLessThan(testCase, trace.errorPower(end), 1e-2, ...
    "QPSK decision-directed FBLMS must converge");
startIdx = Nf + 6 * N + 1;
seg = output(startIdx:end);
refseg = signal(startIdx:startIdx + numel(seg) - 1);
decisions = qpskSlicer(seg);
verifyEqual(testCase, decisions, refseg, ...
    "QPSK decisions must match the reference symbols");
end

function testFblmsPartialTrainingBlockUsesReference(testCase)
% A partial final training block must still use the reference symbols
% for its in-frame training samples (per-sample trainingMask), even
% when useDecisionFeedback is false - flipping those reference symbols
% must change the learned weights.
N = 64;
Nf = 8;
trainLength = 700; % last block spans 641-704, 60 in-frame training
signal = randi([0 1], 1, 700) * 2 - 1;
step = 0.5;
epsilon = 1e-6;
[~, w1, ~] = scfde.equalizers.fblms_equalizer(signal, signal, ...
    trainLength, Nf, N, step, epsilon, false);
flipped = signal;
flipped(641:700) = -flipped(641:700); % flip the partial-block training
[~, w2, ~] = scfde.equalizers.fblms_equalizer(signal, flipped, ...
    trainLength, Nf, N, step, epsilon, false);
verifyGreaterThan(testCase, norm(w1 - w2), 0, ...
    "partial training block reference must affect the learned weights");
end

function testFblmsPartialFinalBlockNoPaddingUpdate(testCase)
% The zero-padded samples of a partial final block must not contribute
% to the adaptive update: with a signal length that is not a multiple
% of the block size, the last block's error power must reflect only the
% in-frame samples, and the equalizer must still converge on the
% training reference.
N = 64;
Nf = 8;
trainLength = 700;  % 10 full blocks + 60 samples (partial last block)
signal = randi([0 1], 1, 700) * 2 - 1;
step = 0.5;
epsilon = 1e-6;
[output, ~, trace] = scfde.equalizers.fblms_equalizer(signal, signal, ...
    trainLength, Nf, N, step, epsilon, false);
verifyEqual(testCase, numel(output), 700, ...
    "output length must equal the input length");
% The last block's error power must be computed on the 60 in-frame
% samples (a padded 64-sample error would be dominated by zeros).
verifyLessThan(testCase, trace.errorPower(end), 0.2, ...
    "final partial block must have converged on its in-frame samples");
startIdx = Nf + 8 * N + 1;
seg = output(startIdx:end);
refseg = signal(startIdx:startIdx + numel(seg) - 1);
verifyLessThan(testCase, mean((seg - refseg).^2), 0.05, ...
    "converged FBLMS must track the reference");
end

function testFblmsNoCircularBoundaryContamination(testCase)
% The block-boundary samples must not be polluted by circular wrap: the
% first Nf samples of each block are dropped (overlap-save) and the
% residual error must be continuous across block boundaries after
% convergence.  The RESIDUAL (output - reference) is used because the
% BPSK signal itself jumps by +/-2 between symbols.
N = 32;
Nf = 4;
trainLength = 640;
signal = randi([0 1], 1, 1024) * 2 - 1;
step = 0.5;
epsilon = 1e-6;
[output, ~, trace] = scfde.equalizers.fblms_equalizer(signal, signal, ...
    trainLength, Nf, N, step, epsilon, false);
% Converged output must track the reference.
startIdx = Nf + 8 * N + 1;
seg = output(startIdx:end);
refseg = signal(startIdx:startIdx + numel(seg) - 1);
mse = mean((seg - refseg).^2);
verifyLessThan(testCase, mse, 0.05, ...
    "converged FBLMS must track the reference");
% Residual continuity: the boundary jump of the residual must be small.
residual = seg - refseg;
residual = residual(1:floor(numel(residual) / N) * N);
resBlocks = reshape(residual, N, []);
boundaryJumps = abs(resBlocks(1, 2:end) - resBlocks(end, 1:end - 1));
verifyLessThan(testCase, max(boundaryJumps), 0.5, ...
    "no circular wrap discontinuity at block boundaries");
end

function testOldCircularBlockFails(testCase)
% Negative regression: the OLD circular-block update (no overlap cache,
% no time-domain constraint G, no contamination discard) must produce a
% worse fit than the strict overlap-save implementation on a MULTIPATH
% input.  With a delayed channel the circular-block implementation
% pollutes the block boundaries and fails to invert the channel, while
% the overlap-save implementation converges.  This guards against
% reverting to the engineering approximation.
N = 64;
Nf = 16;
trainLength = 896;
source = randi([0 1], 1, 1280) * 2 - 1;
% Multipath channel with a main tap at delay 4 and echoes.
h = zeros(1, 12);
h([1, 5, 9]) = [1, 0.5, 0.25];
signal = conv(source, h);
signal = signal(1:numel(source));
step = 0.5;
epsilon = 1e-6;
[output, ~, ~] = scfde.equalizers.fblms_equalizer(signal, source, ...
    trainLength, Nf, N, step, epsilon, false);
startIdx = Nf + 10 * N + 1;
seg = output(startIdx:end);
refseg = source(startIdx:startIdx + numel(seg) - 1);
mseStrict = mean((seg - refseg).^2);
% Old circular-block: FFT over the whole block without overlap, weight
% updated in frequency domain, output taken circularly (no discard).
weights = zeros(N, 1);
outputOld = zeros(1, numel(signal));
for block = 0:floor(numel(signal) / N) - 1
    idx = block * N + 1:block * N + N;
    xb = signal(idx);
    inputSpectrum = fft(xb, N);
    filtered = ifft(weights .* inputSpectrum.').';
    outputOld(idx) = filtered;
    err = source(idx) - filtered;
    errorSpectrum = fft(err, N);
    weights = weights + step * conj(inputSpectrum.') .* ...
        errorSpectrum.' ./ (epsilon + abs(inputSpectrum.').^2);
end
segOld = outputOld(startIdx:end);
refsegOld = source(startIdx:startIdx + numel(segOld) - 1);
mseOld = mean((segOld - refsegOld).^2);
verifyLessThan(testCase, mseStrict, mseOld, ...
    "strict overlap-save must beat the old circular-block update");
end

function testCurveBenchmarkMetrics(testCase)
% Construct a simulation curve and a reference with a known offset, and
% verify the benchmark metrics (log RMSE, zone RMSE, SNR deviation,
% ordering agreement, grade).
snrSim = 0:2:14;
reference.snrDb = 0:2:14;
methodNames = ["A", "B"];
% Reference: method A at 1e-2..1e-5, method B 3x worse.
reference.ber = [
    1e-2, 3e-3, 1e-3, 3e-4, 1e-4, 3e-5, 1e-5, 1e-5
    3e-2, 1e-2, 3e-3, 1e-3, 3e-4, 1e-4, 3e-5, 1e-5
];
% Simulation: method A exactly on reference, method B 2x worse.
berSim = [
    1e-2, 3e-3, 1e-3, 3e-4, 1e-4, 3e-5, 1e-5, 1e-5
    6e-2, 2e-2, 6e-3, 2e-3, 6e-4, 2e-4, 6e-5, 2e-5
];
benchmark = scfde.equalizers.curve_benchmark(berSim, snrSim, ...
    reference, methodNames);
verifyEqual(testCase, benchmark.perMethod.logRmse(1), 0, ...
    "AbsTol", 1e-10, "method A is exactly on the reference");
verifyGreaterThan(testCase, benchmark.perMethod.logRmse(2), 0.1, ...
    "method B deviates from the reference");
verifyEqual(testCase, benchmark.orderAgreement, 1, ...
    "method ordering must agree");
verifyTrue(testCase, ismember(benchmark.grade, ["A", "B", "C", "D"]));
end

function testCurveBenchmarkDifferentSnrGrids(testCase)
% The benchmark must work with DIFFERENT simulation and reference SNR
% grids (different lengths and spacings) without index errors, and the
% ordering agreement must use the interpolated simulation values.
snrSim = [0, 4, 8, 12, 16];      % 5 points, spacing 4
reference.snrDb = [1, 5, 9, 13]; % 4 points, spacing 4, offset by 1
methodNames = ["A", "B"];
reference.ber = [
    5e-3, 8e-4, 1.2e-4, 2e-5
    1.5e-2, 2.4e-3, 3.6e-4, 5.5e-5
];
% Simulation A is the reference curve evaluated on the simulation grid
% (log-linear interpolation), so its log-RMSE must be ~0; simulation B
% is 3x worse.
refLogA = interp1(reference.snrDb, log10(reference.ber(1, :)), ...
    snrSim, "linear", "extrap");
refLogB = interp1(reference.snrDb, log10(reference.ber(2, :)), ...
    snrSim, "linear", "extrap");
berSim = [
    10 .^ refLogA
    3 * 10 .^ refLogB
];
benchmark = scfde.equalizers.curve_benchmark(berSim, snrSim, ...
    reference, methodNames);
% Round-trip interpolation (reference -> simulation grid -> reference)
% leaves a small log-RMSE; 0.01 is the two-way interpolation bound.
verifyEqual(testCase, benchmark.perMethod.logRmse(1), 0, ...
    "AbsTol", 0.01, "method A is exactly on the reference");
verifyEqual(testCase, benchmark.orderAgreement, 1, ...
    "ordering must agree on mismatched grids");
verifyTrue(testCase, all(isfinite(benchmark.coverage(:))), ...
    "coverage must be finite");
end

function testCurveBenchmarkHeterogeneousNaN(testCase)
% Per-method coverage: method A has 6 finite reference points, method B
% only 2 (the rest NaN).  When B's 2 points are fully inside the
% simulation range, B's coverage fraction must be 1 (2/2), not 2/6,
% and B must not be downgraded because of A's extra points.
snrSim = 0:2:10;
reference.snrDb = 0:2:10;
reference.ber = [
    1e-1, 5e-2, 2e-2, 1e-2, 5e-3, 2e-3          % A: 6 points
    3e-2, NaN, NaN, 1e-3, NaN, NaN              % B: 2 points
];
berSim = reference.ber; % both methods match exactly on their points
benchmark = scfde.equalizers.curve_benchmark(berSim, snrSim, ...
    reference, ["A", "B"]);
verifyEqual(testCase, benchmark.coverageFraction(1), 1, ...
    "AbsTol", 1e-10, "method A covers all its 6 finite points");
verifyEqual(testCase, benchmark.coverageFraction(2), 1, ...
    "AbsTol", 1e-10, ...
    "method B must cover all its 2 finite points (2/2, not 2/6)");
verifyEqual(testCase, benchmark.perMethod.logRmse(1), 0, ...
    "AbsTol", 1e-10, "method A matches exactly");
verifyEqual(testCase, benchmark.perMethod.logRmse(2), 0, ...
    "AbsTol", 1e-10, "method B matches exactly on its 2 points");
verifyTrue(testCase, ismember(benchmark.perMethod.grade(2), ["A", "B"]), ...
    "method B must not be downgraded by A's extra points");
end

function testCurveBenchmarkOverallGradeConservative(testCase)
% The overall grade must not be diluted by a well-fitted method with
% many points: method A has 101 exact points, method B has only 1 point
% that is 1 decade off.  The pooled RMSE is small (~0.099) but the
% overall grade must reflect the worst method (B => C), not A.
snrSim = 0:0.1:10;              % 101 points
reference.snrDb = snrSim;
reference.ber = [
    logspace(-1, -5, 101)                % A: exact
    3e-2, NaN(1, 100)                    % B: 1 point, 1 decade off
];
berSim = [
    logspace(-1, -5, 101)                % A matches
    3e-1, NaN(1, 100)                    % B is 1 decade worse
];
benchmark = scfde.equalizers.curve_benchmark(berSim, snrSim, ...
    reference, ["A", "B"]);
verifyEqual(testCase, benchmark.perMethod.grade(1), "A", ...
    "method A is exact and must be grade A");
verifyEqual(testCase, benchmark.perMethod.grade(2), "C", ...
    "method B is 1 decade off and must be grade C");
verifyLessThan(testCase, benchmark.logRmse, 0.15, ...
    "pooled RMSE is diluted below the A threshold");
verifyEqual(testCase, benchmark.overallRmse, ...
    benchmark.perMethod.logRmse(2), "AbsTol", 1e-12, ...
    "overall RMSE must equal the worst method's RMSE");
verifyEqual(testCase, benchmark.grade, "C", ...
    "overall grade must reflect the worst method, not the pooled RMSE");
end

function testCurveBenchmarkAllNanMethodDowngrades(testCase)
% A method with NO reference points at all (all-NaN reference row) must
% bring the overall grade down to D even when another method is exact:
% coverage=[1,0], perGrade=[A,D] must give overall grade D.
snrSim = 0:2:10;
reference.snrDb = 0:2:10;
reference.ber = [
    1e-1, 5e-2, 2e-2, 1e-2, 5e-3, 2e-3   % A: complete reference
    NaN, NaN, NaN, NaN, NaN, NaN          % B: no reference points
];
berSim = [
    1e-1, 5e-2, 2e-2, 1e-2, 5e-3, 2e-3   % A exact
    zeros(1, 6) + eps                      % B simulated, no reference
];
benchmark = scfde.equalizers.curve_benchmark(berSim, snrSim, ...
    reference, ["A", "B"]);
verifyEqual(testCase, benchmark.coverageFraction(1), 1, ...
    "AbsTol", 1e-10, "method A covers all its points");
verifyEqual(testCase, benchmark.coverageFraction(2), 0, ...
    "AbsTol", 1e-10, "method B has zero coverage (no reference)");
verifyEqual(testCase, benchmark.perMethod.grade(1), "A", ...
    "method A is exact and must be grade A");
verifyEqual(testCase, benchmark.perMethod.grade(2), "D", ...
    "method B has no reference and must be grade D");
verifyEqual(testCase, benchmark.grade, "D", ...
    "overall grade must be downgraded to D by the no-reference method");
end

function testCurveBenchmarkCoverageExclusion(testCase)
% Reference points outside the simulation SNR range must be excluded
% from the horizontal SNR deviation (and flagged in coverage), not
% extrapolated.
snrSim = 0:2:10;
reference.snrDb = [-2, 0, 2, 4, 6, 8, 10, 12]; % extends beyond sim
methodNames = ["A"];
reference.ber = [1e-1, 1e-2, 3e-3, 1e-3, 3e-4, 1e-4, 3e-5, 1e-6];
berSim = 10 .^ interp1([-2, 12], [-1, -6], 0:2:10, "linear", "extrap");
benchmark = scfde.equalizers.curve_benchmark(berSim, snrSim, ...
    reference, methodNames);
% Coverage: first and last reference points lie outside the sim range.
verifyEqual(testCase, benchmark.horizontalCoverage(1, 1), false, ...
    "reference point below the sim SNR range must be excluded");
verifyEqual(testCase, benchmark.horizontalCoverage(1, end), false, ...
    "reference point above the sim SNR range must be excluded");
verifyTrue(testCase, all(benchmark.horizontalCoverage(1, 2:end - 1)), ...
    "interior reference points must be covered");
% SNR coverage: 0..10 of the reference are inside the sim range.
verifyEqual(testCase, benchmark.snrCoverage(1, 2:end - 1), ...
    true(1, 6), "interior SNR points must be inside the sim range");
end

function testCurveBenchmarkLowCoverageDowngrades(testCase)
% With only a small fraction of the reference SNR range covered, the
% grade must be downgraded to D (insufficient evidence), even if the
% covered points match exactly.
snrSim = [0, 2];                    % sim covers only 0-2 dB
reference.snrDb = 0:2:10;           % reference spans 0-10 dB
methodNames = ["A"];
reference.ber = 10 .^ linspace(-1, -5, 6);
berSim = reference.ber(1:2);        % sim matches the covered points
benchmark = scfde.equalizers.curve_benchmark(berSim, snrSim, ...
    reference, methodNames);
verifyEqual(testCase, benchmark.perMethod.logRmse(1), 0, ...
    "AbsTol", 1e-10, "covered points match exactly");
verifyLessThan(testCase, benchmark.coverageFraction(1), 0.5, ...
    "coverage fraction must be below 0.5");
verifyEqual(testCase, benchmark.grade, "D", ...
    "low coverage must downgrade the grade to D");
verifyEqual(testCase, benchmark.perMethod.grade(1), "D", ...
    "per-method grade must be downgraded to D");
end

function testCh5ChannelParameterizedAndSensitive(testCase)
% The chapter-5 11-tap channel must be parameterized (delays/power/
% phase) for sensitivity analysis, and the default synthetic model must
% match its documented tap list.
ch = scfde.equalizers.ch5_long_uwa_channel();
delays = [0, 1, 2, 3, 4, 5, 7, 9, 11, 13, 15];
verifyEqual(testCase, numel(ch), delays(end) + 1, ...
    "default channel length must match the 11-tap model");
verifyEqual(testCase, norm(ch), 1, "AbsTol", 1e-12, ...
    "channel must be unit-energy");
active = find(abs(ch) > 1e-12);
verifyEqual(testCase, active, delays + 1, ...
    "default channel must place taps at the documented delays");
% Sensitivity: perturbing the tap phases must change the channel
% (the unit-energy normalization cancels a global gain perturbation).
phaseBase = [0, .5, -1.0, .8, -2.1, .25, -1.5, 1.4, -.8, .9, -2.6];
chPerturbed = scfde.equalizers.ch5_long_uwa_channel( ...
    delays, [], phaseBase + 0.3);
verifyEqual(testCase, numel(chPerturbed), numel(ch), ...
    "perturbed channel must keep the same length");
verifyGreaterThan(testCase, norm(ch - chPerturbed), 1e-3, ...
    "tap-phase perturbation must change the channel");
end

function testHtfdeReliabilityModes(testCase)
% The HTFDE reliability weighting must be selectable via
% cfg.htfdeReliabilityMode: posterior (default), none, or a user
% function handle; the module must run in all modes and the posterior
% and none modes must produce different weightings.
dataSymbols = 192;
N = 256;  % 192 data + 64 UW
imp = [1, 0.4 * exp(1j * 0.3), 0.2 * exp(-1j * 0.6)];
H = fft([imp, zeros(1, N - numel(imp))]);
bits = randi([0 1], 2 * dataSymbols, 1);
bitMatrix = reshape(bits, 2, []);
data = ((1 - 2 * bitMatrix(1, :)) + ...
    1j * (1 - 2 * bitMatrix(2, :))).' / sqrt(2);
uw = exp(1j * pi * (0:63).'.^2 / 64);
tx = [data; uw];
received = ifft(H(:) .* fft(tx));
received = received + 0.1 * (randn(size(received)) + 1j * randn(size(received)));
received = received(:).';
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received]);
src = struct("data", data.', "tx", tx.', "training", tx(1:32).');
baseCfg = struct("noiseVariance", 0.01, "dataSymbols", dataSymbols, ...
    "uwLength", 64, "fftSize", N, "htfdeBranches", 2, ...
    "htfdeIterations", 2, "channelEstimateLength", numel(imp));
cfgP = baseCfg; cfgP.htfdeReliabilityMode = "posterior";
cfgN = baseCfg; cfgN.htfdeReliabilityMode = "none";
cfgF = baseCfg;
cfgF.htfdeReliabilityMode = @(s, nv) 0.5;
r1 = scfde.equalizers.htfde(ch, src, cfgP);
r2 = scfde.equalizers.htfde(ch, src, cfgN);
r3 = scfde.equalizers.htfde(ch, src, cfgF);
verifyTrue(testCase, all(isfinite(r1.outputs{1})) && ...
    all(isfinite(r2.outputs{1})) && all(isfinite(r3.outputs{1})), ...
    "all three reliability modes must produce finite outputs");
verifyNotEqual(testCase, r1.traces{1}.symbolsByIteration(1, :), ...
    r2.traces{1}.symbolsByIteration(1, :), ...
    "posterior and none modes must differ in the first iteration");
end

function testFddaFeedbackAndOuterLoop(testCase)
% Decisive checks requested by the review: the feedback filter B must
% be non-zero after the training segment, changing mu_b must change the
% output, and I_outer=1 vs 3 must produce different iteration
% trajectories.
infoBits = 512;
trainingSymbols = 256;
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
nv = 10^(0/10);
rng(42, "twister");
permutation = randperm(2 * infoBits);
info = randi([0 1], 1, infoBits);
coded = scfde.equalizers.ch4_convolutional_encode(info);
dataSymbols = 1 - 2 * coded(permutation);
training = 1 - 2 * randi([0 1], 1, trainingSymbols);
tx = [training, dataSymbols];
N = numel(tx);
H = fft([imp, zeros(1, N - numel(imp))]);
received = ifft(H .* fft(tx));
received = received + sqrt(nv/2) * (randn(size(received)) + 1j * randn(size(received)));
mkCfg = @(muB, iters) struct("noiseVariance", nv, ...
    "trainingSymbols", trainingSymbols, "fddaBlockLength", 32, ...
    "fddaFfLength", 32, "fddaFbLength", 10, "fddaStepFf", 0.2, ...
    "fddaStepFb", muB, "iterations", iters, ...
    "permutation", permutation, "turboDecoderMode", "Log-MAP");
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received]);
src = struct("data", 1 - 2 * info, "tx", tx, "training", training);
r1 = scfde.equalizers.fdda_teq_true(ch, src, mkCfg(0.01, 1));
verifyGreaterThan(testCase, max(r1.traces{1}.feedbackNorm(:)), 0, ...
    "feedback filter B must be non-zero after training");
% The feedback filter participates in the data-segment output only
% from outer iteration 2 onward (Eq. 4-75: outer=1 feeds zero back),
% so the mu_b sensitivity must be checked with I_outer=3.
rMu0 = scfde.equalizers.fdda_teq_true(ch, src, mkCfg(0, 3));
rMuBig = scfde.equalizers.fdda_teq_true(ch, src, mkCfg(100, 3));
verifyGreaterThan(testCase, ...
    norm(rMu0.outputs{1} - rMuBig.outputs{1}), 1e-6, ...
    "changing mu_b must change the output");
verifyGreaterThan(testCase, ...
    norm(rMuBig.traces{1}.finalB - rMu0.traces{1}.finalB), 1e-12, ...
    "changing mu_b must change the feedback filter B");
rOuter3 = scfde.equalizers.fdda_teq_true(ch, src, mkCfg(0.01, 3));
verifyGreaterThan(testCase, ...
    norm(rOuter3.traces{1}.iterationError - r1.traces{1}.iterationError(1)), ...
    1e-6, "I_outer=3 must produce a different iteration trajectory");
verifyEqual(testCase, numel(rOuter3.traces{1}.iterationError), 3, ...
    "I_outer=3 must record three outer iterations");
% The per-outer-iteration diagnostics must be measured against the SAME
% reference (the transmitted data symbols) and the trajectory must not
% diverge.
mseTrajectory = rOuter3.traces{1}.iterationMse;
verifyTrue(testCase, numel(mseTrajectory) == 3 && ...
    all(isfinite(mseTrajectory)), ...
    "iteration MSE must be finite for all outer iterations");
verifyLessThanOrEqual(testCase, max(mseTrajectory), ...
    1.5 * mseTrajectory(1), ...
    "outer iterations must not diverge (same true-data reference)");
% The DATA segment must genuinely adapt B (Eq. 4-82): with I_outer=3
% the feedback is non-zero from outer 2 (Eq. 4-75), so a mu_b change
% must change the feedbackNorm of the DATA blocks (block index >=
% trainBlocks) and the final B.  With I_outer=1 the data feedback is
% forced to zero, so this check would be vacuous.
trainBlocks = ceil(256 / 32);
rMu0 = scfde.equalizers.fdda_teq_true(ch, src, mkCfg(0, 3));
rMuBig = scfde.equalizers.fdda_teq_true(ch, src, mkCfg(100, 3));
dataFbNorm0 = rMu0.traces{1}.feedbackNorm(:, trainBlocks + 1:end);
dataFbNormBig = rMuBig.traces{1}.feedbackNorm(:, trainBlocks + 1:end);
verifyGreaterThan(testCase, norm(dataFbNormBig - dataFbNorm0), 0, ...
    "data-segment B adaptation must make mu_b visible after training");
% The data-segment B must actually evolve block by block (not frozen
% at the trained value): the feedbackNorm of the last outer iteration
% must differ between the end of training and the end of the data.
lastOuter = rMuBig.traces{1}.feedbackNorm(end, :);
verifyGreaterThan(testCase, ...
    abs(lastOuter(end) - lastOuter(trainBlocks)), 0, ...
    "B must keep adapting across the data blocks of an outer iteration");
end

function testEseDampingDefaultsConsistent(testCase)
% Both chapter-6 production entries must default to the same ESE/PIC
% damping (0.58); the review found 0.65 vs 0.58 inconsistency.
% Lightweight invocations: the default calls would run the full
% end-to-end simulation; pass minimal options to read the defaults.
simulationDir = fullfile(fileparts(mfilename("fullpath")), "..");
cfg1 = scfde.run_chapter6_paper_full_chain(struct( ...
    "frameCount", 1, "runLoadStudy", false, "runComparison", false, ...
    "makePlot", false, "exportData", false), simulationDir);
verifyEqual(testCase, cfg1.config.eseDamping, 0.58, ...
    "paper full chain must default to damping 0.58");
cfg2 = scfde.run_chapter6_spread_spectrum_suite(struct( ...
    "frameCount", 1, "makePlot", false, "exportData", false), simulationDir);
verifyEqual(testCase, cfg2.config.eseDamping, 0.58, ...
    "spread-spectrum suite must default to damping 0.58");
end

function testFddaEquationDenominatorThreeBlocks(testCase)
% The default denominator must be the book Eq. (4-82) scalar
% delta + R^H R with the Eq. (4-75) feedback window; THREE training
% blocks are used so the middle block has past AND future neighbours
% (non-zero feedback Xb), and every block's W and B update is compared
% against a manual block-by-block evaluation of Eq. (4-82).
Nc = 32; Nf = 32; Nb = 10;
fftLength = Nc + 2 * max(Nf, Nb);
numBlocks = 3;
rng(7, "twister");
training = (1 - 2 * randi([0 1], 1, Nc * numBlocks));
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
received = ifft(fft([imp, zeros(1, numel(training) - numel(imp))]).' .* ...
    fft(training).');
received = received + 0.1 * (randn(size(received)) + 1j * randn(size(received)));
received = received.';
params = struct("blockLength", Nc, "ffLength", Nf, "fbLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "outerIterations", 1, ...
    "forgettingF", 0.97, "denomMode", "equation", ...
    "trainLength", Nc * numBlocks, "referenceData", training);
params.decisionFn = @(x) sign(real(x));
[~, trace] = scfde.equalizers.ch4_fdda_teq_core( ...
    received, training, params, @(o, d) d);
Wk = trace.finalW; Bk = trace.finalB;
% Manual block-by-block Eq. (4-82) with the Eq. (4-75) window.
W = ones(fftLength, 1); B = zeros(fftLength, 1);
frontTail = zeros(1, Nf);
xNorm = zeros(1, numBlocks);
for block = 0:numBlocks - 1
    blockStart = block * Nc + 1;
    current = received(blockStart:blockStart + Nc - 1);
    rearStart = blockStart + Nc;
    rearEnd = min(rearStart + Nf - 1, numel(received));
    rear = zeros(1, Nf);
    if rearStart <= numel(received)
        rear(1:rearEnd - rearStart + 1) = received(rearStart:rearEnd);
    end
    inputBlock = [frontTail, current, rear];
    R = fft(inputBlock, fftLength);
    % Eq. (4-75) window over the training sequence.
    fbBlock = scfde.equalizers.ch4_fdda_feedback_block( ...
        training, blockStart - 1, Nc, Nf);
    Xb = fft(fbBlock, fftLength);
    xNorm(block + 1) = norm(Xb);
    filtered = ifft(W .* R.' - B .* Xb.').';
    valid = filtered(Nf + 1:Nf + Nc);
    desired = training(blockStart:blockStart + Nc - 1);
    err = desired - valid;
    errorBlock = zeros(1, fftLength);
    errorBlock(Nf + 1:Nf + Nc) = err;
    E = fft(errorBlock, fftLength);
    denomF = 1e-6 + real(R * R');
    W = W + 0.2 * (conj(R.') .* E.') / denomF;
    wT = ifft(W); wT(Nf + 1:end) = 0; W = fft(wT);
    denomB = 1e-6 + real(Xb * Xb');
    B = B + 0.01 * (conj(Xb.') .* E.') / denomB;
    bT = ifft(B); bT(Nb + 1:end) = 0; B = fft(bT);
    frontTail = current(end - Nf + 1:end);
end
verifyGreaterThan(testCase, xNorm(2), 0, ...
    "the middle block must have a non-zero feedback spectrum");
verifyGreaterThan(testCase, norm(B), 0, ...
    "the feedback filter must be non-zero after three training blocks");
verifyEqual(testCase, Wk, W, "AbsTol", 1e-12, ...
    "kernel W must equal the manual Eq. (4-82) updates");
verifyEqual(testCase, Bk, B, "AbsTol", 1e-12, ...
    "kernel B must equal the manual Eq. (4-82) updates");
verifyEqual(testCase, trace.stepScale(1, 1), 1, ...
    "first block step scale must be gamma^0 = 1");
end

function testFddaWrapperDefaultDenominatorIsEquation(testCase)
% The production wrapper fdda_teq_true must default to the book
% Eq. (4-82) scalar denominator even when cfg.fddaDenomMode is absent
% (regression: the wrapper used to force "bin", overriding the shared
% kernel default).  The wrapper result must equal an explicit
% equation run of the shared kernel and differ from an explicit bin run.
infoBits = 512;
trainingSymbols = 256;
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
nv = 10^(2/10);
rng(11, "twister");
permutation = randperm(2 * infoBits);
info = randi([0 1], 1, infoBits);
coded = scfde.equalizers.ch4_convolutional_encode(info);
dataSymbols = 1 - 2 * coded(permutation);
training = 1 - 2 * randi([0 1], 1, trainingSymbols);
tx = [training, dataSymbols];
N = numel(tx);
H = fft([imp, zeros(1, N - numel(imp))]);
received = ifft(H .* fft(tx));
received = received + sqrt(nv/2) * (randn(size(received)) + 1j * randn(size(received)));
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received]);
src = struct("data", 1 - 2 * info, "tx", tx, "training", training);
baseCfg = struct("noiseVariance", nv, "trainingSymbols", trainingSymbols, ...
    "fddaBlockLength", 32, "fddaFfLength", 32, "fddaFbLength", 10, ...
    "fddaStepFf", 0.2, "fddaStepFb", 0.01, "iterations", 1, ...
    "fddaForgetting", 0.97, "permutation", permutation, ...
    "turboDecoderMode", "Log-MAP");
rDefault = scfde.equalizers.fdda_teq_true(ch, src, baseCfg);
cfgEq = baseCfg; cfgEq.fddaDenomMode = "equation";
rEquation = scfde.equalizers.fdda_teq_true(ch, src, cfgEq);
cfgBin = baseCfg; cfgBin.fddaDenomMode = "bin";
rBin = scfde.equalizers.fdda_teq_true(ch, src, cfgBin);
verifyEqual(testCase, rDefault.traces{1}.finalW, ...
    rEquation.traces{1}.finalW, "AbsTol", 1e-12, ...
    "production default must run the equation denominator");
verifyEqual(testCase, rDefault.traces{1}.finalB, ...
    rEquation.traces{1}.finalB, "AbsTol", 1e-12, ...
    "production default must run the equation denominator (B)");
verifyGreaterThan(testCase, ...
    norm(rDefault.traces{1}.finalW - rBin.traces{1}.finalW), 1e-6, ...
    "production default must differ from the bin engineering mode");
end

function testFddaForgettingIndexedByOuterIteration(testCase)
% Eq. (4-82) uses gamma_f^i / gamma_b^i with i the OUTER ITERATION
% index: ALL blocks inside the same outer iteration share the same
% scale, and the next outer iteration scales by gamma.  A per-block
% (global block counter) implementation must fail this test.
Nc = 32; Nf = 32; Nb = 10;
fftLength = Nc + 2 * max(Nf, Nb);
rng(3, "twister");
% Frame of 2 blocks: 1 training block + 1 data block.
training = (1 - 2 * randi([0 1], 1, Nc));
dataBlock = (1 - 2 * randi([0 1], 1, Nc));
tx = [training, dataBlock];
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
received = (ifft(fft([imp, zeros(1, numel(tx) - numel(imp))]) .* ...
    fft(tx)) + 0.05 * (randn(1, numel(tx)) + 1j * randn(1, numel(tx))));
gamma = 0.9;
params = struct("blockLength", Nc, "ffLength", Nf, "fbLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "outerIterations", 2, ...
    "forgettingF", gamma, "denomMode", "equation", ...
    "trainLength", Nc, "referenceData", dataBlock);
params.decisionFn = @(x) sign(real(x));
[~, trace] = scfde.equalizers.ch4_fdda_teq_core( ...
    received, training, params, @(o, d) d);
ss = trace.stepScale;   % outerIterations x numBlocks
verifyEqual(testCase, ss(1, 1), 1, "AbsTol", 1e-12, ...
    "first outer iteration scale must be gamma^0 = 1");
verifyEqual(testCase, ss(1, 2), ss(1, 1), "AbsTol", 1e-12, ...
    "all blocks of outer 1 must share the same scale");
verifyEqual(testCase, ss(2, 1), gamma, "AbsTol", 1e-12, ...
    "outer 2 scale must be gamma^1");
verifyEqual(testCase, ss(2, 2), ss(2, 1), "AbsTol", 1e-12, ...
    "all blocks of outer 2 must share the same scale");
verifyEqual(testCase, trace.stepScaleF, trace.stepScaleB, ...
    "AbsTol", 1e-12, ...
    "default gamma_f = gamma_b assumption must hold");
end

function testFddaFeedbackBlockWindow(testCase)
% Book Eq. (4-75): the feedback block is [past estimates; 0_N; future
% estimates] -- the current block's own N positions must be ZERO and
% the front/rear windows must equal the neighbouring estimates.
N = 8; Nf = 4;
rng(5, "twister");
estimates = (1 - 2 * randi([0 1], 1, 3 * N));   % 3 blocks of 8
% block 1 (0-based index 1, sample offset 8): middle must be zero,
% front = estimates(5:8), rear = estimates(17:20)
fb = scfde.equalizers.ch4_fdda_feedback_block(estimates, N, N, Nf);
verifyEqual(testCase, fb(1:Nf), estimates(N - Nf + 1:N), ...
    "front window must equal the previous estimates");
verifyEqual(testCase, fb(Nf + 1:Nf + N), zeros(1, N), ...
    "current block positions must be strictly zero");
verifyEqual(testCase, fb(N + Nf + 1:end), estimates(2 * N + 1:2 * N + Nf), ...
    "rear window must equal the following estimates");
% frame edge: block 0 has no past -> front padded with zeros
fb0 = scfde.equalizers.ch4_fdda_feedback_block(estimates, 0, N, Nf);
verifyEqual(testCase, fb0(1:Nf), zeros(1, Nf), ...
    "edge block front must be zero (no past estimates)");
verifyEqual(testCase, fb0(Nf + 1:Nf + N), zeros(1, N), ...
    "edge block middle must be zero");
% first turbo equalization: no prior information -> whole block zero
verifyEqual(testCase, ...
    scfde.equalizers.ch4_fdda_feedback_block(zeros(1, 3 * N), N, N, Nf), ...
    zeros(1, N + 2 * Nf), "no-prior feedback must be all zero");
end

function testCh5ChannelInputValidation(testCase)
% The parameterized chapter-5 channel must reject invalid inputs:
% duplicate delays, negative power, mismatched lengths.
ch = scfde.equalizers.ch5_long_uwa_channel();
verifyEqual(testCase, norm(ch), 1, "AbsTol", 1e-12, ...
    "unit-energy channel");
verifyError(testCase, ...
    @() scfde.equalizers.ch5_long_uwa_channel([0, 0], [1, 1], [0, 0]), ...
    "SCFDE:Channel", "duplicate delays must be rejected");
verifyError(testCase, ...
    @() scfde.equalizers.ch5_long_uwa_channel([0, 1], [-1, 1], [0, 0]), ...
    "SCFDE:Channel", "negative power must be rejected");
verifyError(testCase, ...
    @() scfde.equalizers.ch5_long_uwa_channel([0, 1, 2], [1, 1], [0, 0]), ...
    "SCFDE:Channel", "length mismatch must be rejected");
verifyError(testCase, ...
    @() scfde.equalizers.ch5_long_uwa_channel([0, 1], [0, 0], [0, 0]), ...
    "SCFDE:Channel", "all-zero power must be rejected (NaN guard)");
verifyError(testCase, ...
    @() scfde.equalizers.ch5_long_uwa_channel([3, 0], [1, 1], [0, 0]), ...
    "SCFDE:Channel", "unsorted delays must be rejected");
end

function testFblmsProductionEntryReproducible(testCase)
% The unified production entry with the QPSK scenario must be
% DETERMINISTIC for a fixed configuration: the same seed must reproduce
% the same error count.  Note: the book Fig. 4-24 algorithm uses the
% scalar block-energy denominator, which converges more slowly than the
% earlier per-bin normalization; with the unified QPSK scenario's short
% training segment (64 symbols) the equalizer only partially adapts, so
% this test pins determinism and the CI consistency rather than a
% specific BER value.
addpath(fullfile(testCase.TestData.papersDir, "engineering_simulation"));
opts = struct("equalizers", {"fblms"}, "scenario", "qpsk", ...
    "snrDb", 18, "symbols", 8, "frameCount", 10, ...
    "makePlot", false, "randomSeed", 42);
r1 = run_unified_equalizer(opts);
r2 = run_unified_equalizer(opts);
verifyEqual(testCase, r1.totalBits, r2.totalBits, ...
    "deterministic total bits");
verifyEqual(testCase, r1.errorBits, r2.errorBits, ...
    "deterministic error count for the fixed seed");
verifyEqual(testCase, r1.ber, r2.ber, ...
    "deterministic BER for the fixed seed");
verifyTrue(testCase, r1.ber >= r1.berLower95 && ...
    r1.ber <= r1.berUpper95, ...
    "BER must lie inside the reported 95% CI");
end
