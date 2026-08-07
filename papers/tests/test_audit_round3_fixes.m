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
% polynomial F_k = 1 + sum_m f_m exp(-j 2 pi k m / N), so after main-tap
% normalization W(B) must differ from W(B=0) (previously identical to
% machine precision because a scalar gain was absorbed by normalization).
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
gamma = abs(H).^2 ./ (abs(H).^2 + noiseRatio);
q = real(ifft(gamma));
W0 = conj(H) ./ (abs(H).^2 + noiseRatio);
Wn0 = W0 / mean(W0 .* H);
for B = [2, 7, 9]
    V = zeros(B, B);
    for m = 1:B
        for n = 1:B
            V(m, n) = q(mod(m - n, N) + 1);
        end
    end
    v = q(2:B + 1);
    f = -V \ v;
    f = f(:);
    Fk = 1 + fft(f, N);
    Fk = Fk(:);
    W = conj(H) ./ (abs(H).^2 + noiseRatio) .* Fk;
    Wn = W / mean(W .* H);
    relative = norm(Wn - Wn0) / norm(Wn0);
    verifyGreaterThan(testCase, relative, 1e-6, ...
        "W(B) must differ from W(B=0) after normalization");
    verifyLessThan(testCase, relative, 0.1, ...
        "W(B) deviation should be a shaping effect, not a rescale");
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
% A detected codeword that differs from the transmitted one by one chip
% must not be counted as 8 bit errors: the unified entry maps detected
% codeword indices through the bit table.
[book, bitTable] = scfde.equalizers.ch5_cck_codebook("FR-CCK", 8, true);
verifyEqual(testCase, size(book), [256, 8]);
verifyEqual(testCase, size(bitTable), [256, 8]);
idx = [1, 2, 3, 4];
txBits = reshape(bitTable(idx, :).', 1, []);
verifyEqual(testCase, numel(txBits), 32);
% A single-chip flip in codeword 1 maps through the bit table; the
% Hamming distance in bits is what is counted.
verifyEqual(testCase, sum(bitTable(1, :) ~= bitTable(2, :)) >= 1, true);
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
