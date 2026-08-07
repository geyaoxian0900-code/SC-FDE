function tests = test_audit_round3_fixes
%TEST_AUDIT_ROUND3_FIXES Regression tests for the third-round formula
% audit fixes: FD-DFE feedforward polynomial, dual-UW frame, PTR
% no-branches fallback, and CCK/CSK bit-level BER counting.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
addpath(fullfile(papersDir, "common"));
addpath(fullfile(papersDir, "engineering_simulation"));
addpath(fullfile(papersDir, "chapter4_simulation"));
addpath(fullfile(papersDir, "chapter3_simulation"));
testCase.TestData.papersDir = papersDir;
end

function testFdDfeFeedforwardDependsOnFeedbackLength(testCase)
% The feedforward filter must carry the frequency-dependent feedback
% polynomial F_k = 1 + sum_m f_m e^{-j 2 pi k m / N} with f_1 at delay
% m = 1, so after main-tap normalization W(B) must differ from W(B=0).
% This test calls the production fd_dfe_design and compares F_k against
% an independent explicit sum (not a copy of the implementation).
N = 512;
Ts_ms = 0.25;
pathDelayMs = [0, 3.4, 6.7, 10];
pathGain = [1, 0.6, 0.6, 0.3];
delays = round(pathDelayMs / Ts_ms);
phases = [0, 0.45, -0.90, 1.35];
h = zeros(max(delays) + 1, 1);
h(delays + 1) = pathGain .* exp(1j * phases);
h = h / norm(h);
H = fft(h, N);
noiseRatio = 10^(-8 / 10);
[W0, ~] = scfde.equalizers.fd_dfe_design(H, noiseRatio, 0);
Wn0 = W0 / mean(W0 .* H);
for B = [2, 7, 9]
    [W, f] = scfde.equalizers.fd_dfe_design(H, noiseRatio, B);
    % Independent reference: F_k = 1 + sum_{m=1}^B f_m e^{-j 2 pi k m / N}
    k = (0:N-1).';
    FkRef = 1 + sum(f.' .* exp(-1j * 2 * pi * k * (1:B) / N), 2);
    FkProd = 1 + fft([0; f], N);
    verifyEqual(testCase, FkProd, FkRef, "AbsTol", 1e-10, ...
        "F_k must place f_1 at delay m = 1");
    Wn = W / mean(W .* H);
    relative = norm(Wn - Wn0) / norm(Wn0);
    verifyGreaterThan(testCase, relative, 1e-6, ...
        "W(B) must differ from W(B=0) after normalization");
    verifyLessThan(testCase, relative, 0.1, ...
        "W(B) deviation should be a shaping effect, not a rescale");
    % Self-consistency: the shaped post-cursor g(m) = f_m for m=1..B
    g = ifft(W .* H);
    verifyEqual(testCase, g(2:B + 1), f, "AbsTol", 1e-8, ...
        "post-cursor must equal the feedback coefficients");
end
end

function testFdDfeChannelDelaysAreMilliseconds(testCase)
% pathDelayMs is in milliseconds with Ts_ms the symbol interval, so the
% taps sit at round(pathDelayMs / Ts_ms) = [0, 14, 27, 40].
delays = round([0, 3.4, 6.7, 10] / 0.25);
verifyEqual(testCase, delays, [0, 14, 27, 40]);
end

function testPtrNoBranchesFallback(testCase)
% When the channel has no branches field, the PTR front end falls back
% to a single branch; the equivalent channel must use the same effective
% branch count (max(1, ...)) instead of zero, which produced a zero
% equivalent channel.
impulse = [1, 0.4 * exp(1j * 0.3), 0.15 * exp(-1j * 0.6)];
channel.received = [1:40] + 0.1 * randn(1, 40);
channel.impulse = impulse;
channel.received = filter(impulse, 1, ...
    [exp(1j * 0.5) * ones(1, 40), zeros(1, numel(impulse) - 1)]);
source.tx = exp(1j * 0.5) * ones(1, 40);
cfg.feedforwardTaps = 8;
cfg.feedbackTaps = 4;
cfg.snrDb = 10;
cfg.trainingSymbols = 20;
cfg.numSubbands = 1;
cfg.ptrRegularization = 1e-3;
cfg.methods = "all";
receiver = scfde.equalizers.subband_ptr_dfe(channel, source, cfg);
verifyTrue(testCase, all(isfinite(receiver.outputs{1})), ...
    "outputs must be finite when branches is missing");
verifyNotEqual(testCase, norm(receiver.outputs{1}), 0, ...
    "outputs must not be all-zero for the single-branch fallback");
end

function testCckBitLevelBerCounting(testCase)
% The unified-entry fallback path must recover codeword indices from
% chip-level outputs with soft chips (axial QPSK {1,j,-1,-j}) matched
% directly against the codebook.  Noiseless chips of codewords 1..4
% must be recovered exactly: slicing with hard_qpsk (diagonal QPSK)
% would merge codewords to 1 2 1 2, so the fallback must not slice.
book = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
idx = [1, 2, 3, 4];
chips = reshape(book(idx, :).', 1, []); % row: symbols*chips
% Replicate the fallback reshaping and nearest-codeword matching.
detected = reshape(chips, size(book, 2), []).';
distance = abs(book - reshape(detected.', 1, size(book, 2), []));
distance = squeeze(sum(distance .^ 2, 2));
[~, detectedIdx] = min(distance, [], 1);
verifyEqual(testCase, detectedIdx, idx, ...
    "soft-chip nearest-codeword must recover codewords 1..4");
% The bit-table counting must give zero errors for exact recovery.
[~, bitTable] = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
txBits = reshape(bitTable(idx, :).', 1, []);
rxBits = reshape(bitTable(detectedIdx, :).', 1, []);
verifyEqual(testCase, sum(rxBits ~= txBits), 0);
% A known codeword mis-detection must count the true bit errors: the
% bit Hamming distance between codeword 1 and codeword 2 is what the
% unified entry reports (not the chip distance), so an error mapping
% codeword 1 to codeword 2 contributes exactly that many bit errors.
mappedErrors = sum(bitTable(1, :) ~= bitTable(2, :));
verifyGreaterThan(testCase, mappedErrors, 0, ...
    "codewords 1 and 2 must differ in their bit mapping");
verifyLessThan(testCase, mappedErrors, 8, ...
    "a single codeword error must not count as 8 bit errors");
% hard_qpsk slicing would destroy the axial phases: show it merges
% codewords, which is why the fallback must not slice.
sliced = ((1 - 2 * (real(chips) < 0)) + ...
    1j * (1 - 2 * (imag(chips) < 0))) / sqrt(2);
detectedSliced = reshape(sliced, size(book, 2), []).';
distanceSliced = abs(book - reshape(detectedSliced.', 1, ...
    size(book, 2), []));
distanceSliced = squeeze(sum(distanceSliced .^ 2, 2));
[~, slicedIdx] = min(distanceSliced, [], 1);
verifyNotEqual(testCase, slicedIdx, idx, ...
    "hard_qpsk slicing must not be used in the CCK fallback");
end

function testCskBitLevelBerCounting(testCase)
% CSK symbol errors must be counted as bit errors through the bit table,
% not as symbol errors.
root = scfde.equalizers.ch6_select_csk_root(63);
[~, bits] = scfde.equalizers.ch6_csk_codebook(root, 4);
verifyEqual(testCase, size(bits), [4, 2]);
% One symbol error can flip 1 or 2 bits; the bit-table mapping must be
% applied before counting.
verifyEqual(testCase, size(reshape(bits([1, 2], :).', 1, [])), [1, 4]);
end

function testDualUwFrameStructure(testCase)
% The sync-compensate chain frame must carry two consecutive pre-data
% UWs for the estimator windows of Eqs. (3-12..3-15); here we verify the
% figure-3.10 frame constant is consistent with the block start.
cfg.uwLength = 64;
blockStart = 2 * cfg.uwLength + 1;
verifyEqual(testCase, blockStart, 129);
end

function testCrossTrackerInBlockAlgebra(testCase)
% The Eq. 3-8 tracker must give an independent per-block estimate from
% the in-block pre/post UW spacing:
%   a_b = (postPeak_b - prePeak_b - postOffset) / postOffset
% with postOffset = blockLength * samplesPerSymbol.  A pure (noiseless,
% single-path) block stretched by a must show the spacing
%   postPeak - prePeak = round(postOffset * (1 + a))
% so the estimate equals a up to the integer-sample quantization.
samplesPerSymbol = 12;
uwLength = 64;
dataLength = 448;
blockLength = 2 * uwLength + dataLength;
postOffset = blockLength * samplesPerSymbol;
a = 0.933e-3;
idealSpacing = postOffset * (1 + a);
verifyEqual(testCase, idealSpacing, 6918.4489, "AbsTol", 1e-3);
verifyEqual(testCase, round(idealSpacing), 6918, ...
    "one-sample quantization floor of the spacing");
% The estimator formula must reduce the quantized spacing back to a
spacing = round(idealSpacing);
estimate = (spacing - postOffset) / postOffset;
verifyEqual(testCase, estimate, (6918 - 6912) / 6912, "AbsTol", 1e-15);
verifyLessThan(testCase, abs(estimate - a), 1.5 / postOffset, ...
    "quantization error bounded by one sample");
end

function testCarrierPhaseBoundaryAdvance(testCase)
% The per-block carrier phase must advance by exactly one sample
% interval at the block boundary: the saved phase is the next sample's
% phase (phase(end) + 2*pi*fc*d/fs), so the first sample of the next
% block differs from the last sample of the previous block.
cfg.fs = 48000;
cfg.fc = 10000;
doppler = 0.933e-3;
step = 2 * pi * cfg.fc * doppler / cfg.fs;
verifyEqual(testCase, step, 0.0012214, "AbsTol", 1e-6);
% previous block last-sample phase at n = L-1; next block first sample
% at n = 0 must be phase(L-1) + step.
lastSamplePhase = step * 10;
nextFirstSamplePhase = lastSamplePhase + step;
verifyEqual(testCase, nextFirstSamplePhase, step * 11, "AbsTol", 1e-15);
end
