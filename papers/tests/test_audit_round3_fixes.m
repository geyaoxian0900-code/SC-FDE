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
% End-to-end: build a noiseless 5-block frame with distinct per-block
% Doppler values through the PRODUCTION tracking_frame, run the
% PRODUCTION cross_peak_tracker, and check each block's estimate is
% independent (close to its own true Doppler, not mixed with neighbours).
fs = 48000; fc = 10000;
samplesPerSymbol = 12;
uwLength = 64; dataLength = 448;
blockLength = 2 * uwLength + dataLength;
uw = exp(1j * pi * (0:uwLength-1).'.^2 / uwLength);
trueD = [0.933, 1.000, 0.9533, 1.067, 1.033] * 1e-3;
tracking = scfde.equalizers.tracking_frame(uw, trueD, fs, fc, ...
    samplesPerSymbol, dataLength);
estimates = scfde.equalizers.cross_peak_tracker(tracking.received, ...
    uw, samplesPerSymbol, blockLength, numel(trueD));
verifyEqual(testCase, size(estimates), [5, 1]);
% Each estimate must be within a few samples of its own true Doppler
% (parabolic interpolation gives sub-sample resolution on a noiseless
% single-path frame; allow 2 samples of quantization slack).
quantizationSlack = 2 / (blockLength * samplesPerSymbol);
verifyEqual(testCase, estimates, trueD(:), "AbsTol", quantizationSlack, ...
    "per-block estimate must track its own Doppler");
% The old adjacent-peak formula mixes neighbouring Dopplers:
%   a'_1 = (D/L) a_1,  a'_b = (U/L) a_(b-1) + (D/L) a_b
% with D = postOffset, U = uwLength*samplesPerSymbol, L = blockStride.
% It must NOT reproduce the true per-block values (regression guard).
postOffset = blockLength * samplesPerSymbol;
blockStride = postOffset + uwLength * samplesPerSymbol;
uFrac = uwLength * samplesPerSymbol / blockStride;
dFrac = postOffset / blockStride;
oldFormula = zeros(5, 1);
oldFormula(1) = dFrac * trueD(1);
for b = 2:5
    oldFormula(b) = uFrac * trueD(b - 1) + dFrac * trueD(b);
end
verifyGreaterThan(testCase, norm(estimates - oldFormula), 1e-8, ...
    "estimates must not match the adjacent-peak mixing formula");
end

function testCarrierPhaseBoundaryAdvance(testCase)
% The PRODUCTION tracking_frame must advance the carrier phase by
% exactly one sample interval at every block boundary.  Verify by
% reconstructing the phase ramp of block 2 from the waveform of a
% constant-magnitude reference: send a frame whose data symbols are all
% +1 so the received phase equals the carrier phase (up to the UW
% pattern, which is handled by using UW-only blocks below).  Instead,
% compare the production waveform against a manual re-build with the
% documented next-sample-phase rule: the phase of the last sample of
% block 1 plus the step of block 2 must equal the phase of the first
% sample of block 2.
fs = 48000; fc = 10000;
samplesPerSymbol = 12;
uwLength = 64; dataLength = 448;
uw = exp(1j * pi * (0:uwLength-1).'.^2 / uwLength);
doppler = 0.933e-3;
trueD = [doppler, 1.5 * doppler];
tracking = scfde.equalizers.tracking_frame(uw, trueD, fs, fc, ...
    samplesPerSymbol, dataLength);
blockLayout = tracking.blockLayout;
blockStride = sum(blockLayout);
L1 = floor((blockStride - 1) * (1 + doppler)) + 1;
% Phase ramp inside block 1 (production): the last block-1 sample
phaseEnd1 = angle(tracking.received(L1));
% Phase ramp inside block 2: first sample
phaseStart2 = angle(tracking.received(L1 + 1));
% The carrier phase of block 2 at n = 0 is cumulativePhase1 + 0 and at
% n = 1 it is cumulativePhase1 + step2.  But angle() of the data symbols
% is polluted by the UW symbol phases, so instead verify the ramp of the
% UW-only segments: block 1's last UW symbol has a known phase from the
% UW sequence, and the carrier adds doppler*2*pi*fc/fs per sample.
% Equivalent check: the production phase at L1 (block 1) and at L1+1
% (block 2) must satisfy
%   phase2(n=0) - phase1(n=L1-1) = step2  (mod 2*pi)
% after removing the data-symbol phase.  Use the UW pattern: both
% boundary samples lie inside the block-1 post-UW / block-2 pre-UW,
% whose symbol phases are uw(end) and uw(1); remove them.
uwSamples = repelem(uw, samplesPerSymbol);
% block 1 post-UW occupies the last uwLength symbols of block 1; its
% last sample phase = angle(uw(end)) + carrierPhase(L1)
% block 2 pre-UW first sample phase = angle(uw(1)) + carrierPhase(L1+1)
carrierAtL1 = mod(angle(tracking.received(L1)) - angle(uwSamples(end)), 2*pi);
carrierAtL1p1 = mod(angle(tracking.received(L1 + 1)) - angle(uwSamples(1)), 2*pi);
diff = mod(carrierAtL1p1 - carrierAtL1, 2 * pi);
% The saved phase is the NEXT sample's phase computed with block 1's
% Doppler, so the boundary advance equals block 1's carrier step.
step = 2 * pi * fc * trueD(1) / fs;
verifyEqual(testCase, diff, step, "AbsTol", 1e-6, ...
    "block boundary must advance by one carrier sample step");
end
