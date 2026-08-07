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
step = 0.3;
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
step = 0.3;
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
step = 0.3;
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
step = 0.3;
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
step = 0.3;
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
step = 0.3;
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

function testFblmsProductionEntryReproducible(testCase)
% The unified production entry with the QPSK scenario must reproduce
% the documented result for a fixed configuration: symbols=8,
% frameCount=10, snrDb=18, randomSeed=42 gives BER ~ 0.0107
% (12 errors / 1120 bits) with the 4-quadrant decision function.
% This pins the production configuration that produced the reported
% improvement over the old BPSK-slicing BER of 0.0295.
addpath(fullfile(testCase.TestData.papersDir, "engineering_simulation"));
opts = struct("equalizers", {"fblms"}, "scenario", "qpsk", ...
    "snrDb", 18, "symbols", 8, "frameCount", 10, ...
    "makePlot", false, "randomSeed", 42);
r = run_unified_equalizer(opts);
verifyEqual(testCase, r.totalBits, 1120, ...
    "production configuration must count 1120 bits");
verifyEqual(testCase, r.errorBits, 12, ...
    "production configuration must reproduce 12 bit errors");
verifyLessThan(testCase, abs(r.ber - 0.01071), 1e-4, ...
    "production BER must reproduce the documented value");
verifyGreaterThan(testCase, r.berLower95, 0.005, ...
    "95% CI lower bound must be consistent");
verifyLessThan(testCase, r.berUpper95, 0.02, ...
    "95% CI upper bound must be consistent");
end
