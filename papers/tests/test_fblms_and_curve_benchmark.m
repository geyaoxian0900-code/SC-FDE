function tests = test_fblms_and_curve_benchmark
%TEST_FBLMS_AND_CURVE_BENCHMARK Tests for the strict overlap-save FBLMS
% equalizer (book Fig. 4-25) and the curve benchmark framework.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
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
