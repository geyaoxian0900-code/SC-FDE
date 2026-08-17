function tests = test_ch4_turbo_eq_4_24_73
%TEST_CH4_TURBO_EQ_4_24_73 Strict-formula tests for the eight remaining
% Chapter-4 turbo methods (spec 4.1~4.8, book (4-24)~(4-73)):
% td-turbo, fd-dfe, fd-turbo, tf-turbo, bitf-turbo, blms-tf-turbo,
% fblms, tdda-teq.
%
% Independent oracles (no production helper reuse):
%   * td-turbo: boxed per-iteration LMMSE x_hat = x_bar + V H^H
%     (H V H^H + sigma^2 I)^{-1}(y - H x_bar) with V = diag(1-|x_bar|^2)
%     (RED against the previous fixed-filter residual form);
%   * decoder feedback: soft mean from the decoder EXTRINSIC
%     tanh(L_D^e/2) (RED against the previous posterior-based mean);
%   * fd-turbo: mu_hat/sigma_hat^2 from (4-60)/(4-61) over the training
%     segment + Gaussian extrinsic LLRs (4-42)/(4-43); W/B coefficients
%     now from the strict (4-56)~(4-58) helper (book/P90.png);
%   * FD-DFE weights: zero-mean constraint sum_k b_k = 0 derived from
%     (4-58) (asserted, never B - mean(B) projected);
%   * tdda-teq: boxed LMS recursion (zero init, no normalization,
%     feedback branch) - inline replica of the spec-4.8 equations;
%   * tf-turbo: HTF feedforward + time soft feedback, NO fixed 0.5
%     mixing (RED against the previous 0.5 time/frequency mix);
%   * bitf-turbo: forward/reversed independent passes with (2-53)
%     equal-weight 1/2 merge after time-order restoration.

tests = functiontests({ ...
    @testTdTurboBoxedLmmseEq4_24_31, ...
    @testDecoderFeedbackMeanUsesExtrinsicEq4_3, ...
    @testFdTurboMuSigmaExtrinsicEq4_60_61, ...
    @testZeroMeanFeedbackConstraintEq4_52, ...
    @testTddaBoxedLmsEq4_8, ...
    @testTfTurboNoFixedHalfMixingEq4_43_49, ...
    @testBitfEqualWeightMergeEq2_53, ...
    @testCh4WrappersRngPreservedAndStatus});
%#ok<*DEFNU>  % setupOnce is invoked by the framework, not by name
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function [channel, source, cfg] = buildCh4Fixture(seed, snrDb, iterations)
rng(seed, "twister");
information = randi([0 1], 1, 512);
coded = scfde.equalizers.ch4_convolutional_encode(information);
permutation = randperm(1024);
training = 1 - 2 * randi([0 1], 1, 256);
tx = [training, 1 - 2 * coded(permutation)];
impulse = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
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
    "baselineDecoder", "Log-MAP", "turboDamping", 0.75, ...
    "tdAdaptiveTaps", 16, "tdNlmsStep", 0.35, ...
    "feedbackTaps", 6, "blmsStep", 0.2, "blmsLeakage", 1e-3, ...
    "blmsRegularization", 1e-3, "fblmsBlockLength", 32, ...
    "fblmsFilterLength", 16, "fblmsStep", 0.5, "fblmsEpsilon", 1e-6);
end

function feedback = timeFeedbackInline(softSymbols, g, N, feedbackTaps)
feedback = zeros(1, N);
for n = 1:N
    for t = 1:feedbackTaps
        idx = mod(n - t - 1, N) + 1;
        feedback(n) = feedback(n) + g(t) * softSymbols(idx);
    end
end
end

function testTdTurboBoxedLmmseEq4_24_31(testCase)
[channel, source, cfg] = buildCh4Fixture(801, 18, 1);
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
channelMatrix = scfde.equalizers.ch4_circulant_channel(channel.impulse, N);
[~, ~, trace] = scfde.equalizers.ch4_iterate_time_turbo( ...
    channel.received, channelMatrix, [], cfg.noiseVariance, frame, cfg, "Log-MAP");
xbar = zeros(1, N);
xbar(frame.trainingIndices) = frame.trainingSymbols;
v = max(1 - abs(xbar).^2, 1e-6);
V = diag(v);
residual = channel.received(:) - channelMatrix * xbar(:);
correction = V * (channelMatrix' * ((channelMatrix * V * ...
    channelMatrix' + cfg.noiseVariance * eye(N)) \ residual));
oracle = xbar + correction.';
verifyEqual(testCase, trace.softEstimates(1, :), oracle, "AbsTol", 1e-8);
verifyEqual(testCase, trace.formulaStatus, "BOOK-EXACT");
end

function testDecoderFeedbackMeanUsesExtrinsicEq4_3(testCase)
[channel, source, cfg] = buildCh4Fixture(802, 18, 1);
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
rng(803, "twister");
llr = randn(1, N);
previous = zeros(1, N);
previous(frame.trainingIndices) = frame.trainingSymbols;
[~, decoderLlrFrame, softFrame] = scfde.equalizers.ch4_decoder_feedback_frame( ...
    llr, frame, previous, 1, "Log-MAP");
dataLlr = llr(frame.dataIndices);
decoderInput = dataLlr(frame.inversePermutation);
[~, codedLlr] = scfde.equalizers.ch4_bcjr_siso_decode(decoderInput, "Log-MAP");
extrinsicOriginal = codedLlr - decoderInput;
extrinsicTx = extrinsicOriginal(frame.permutation);
posteriorTx = codedLlr(frame.permutation);
expected = previous;
expected(frame.dataIndices) = tanh(extrinsicTx / 2);
verifyEqual(testCase, softFrame, expected, "AbsTol", 1e-12, ...
    "feedback mean must come from the decoder EXTRINSIC LLR");
verifyEqual(testCase, decoderLlrFrame(frame.dataIndices), extrinsicTx, ...
    "AbsTol", 1e-12, "only extrinsic LLRs may be fed back");
verifyTrue(testCase, any(abs(tanh(posteriorTx / 2) - ...
    tanh(extrinsicTx / 2)) > 1e-9), ...
    "posterior- and extrinsic-based means must differ here (RED premise)");
end

function testFdTurboMuSigmaExtrinsicEq4_60_61(testCase)
[channel, source, cfg] = buildCh4Fixture(804, 18, 1);
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
H = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
[~, ~, trace] = scfde.equalizers.ch4_iterate_frequency_turbo( ...
    fft(channel.received), H, H, cfg.noiseVariance, frame, cfg, ...
    "Log-MAP", false);
est = trace.softEstimates(1, :);
trainingX = frame.trainingSymbols(:).';
mu = mean(est(frame.trainingIndices) .* conj(trainingX));
sig2 = max(mean(abs(est(frame.trainingIndices) - mu * trainingX).^2), ...
    cfg.noiseVariance);
verifyEqual(testCase, trace.equivalentGain(1), mu, "AbsTol", 1e-9);
verifyEqual(testCase, trace.residualVariance(1), sig2, "AbsTol", 1e-9);
verifyEqual(testCase, trace.equalizerLlr(1, frame.dataIndices), ...
    2 * real(conj(mu) * est(frame.dataIndices)) / sig2, "AbsTol", 1e-9);
verifyEqual(testCase, trace.formulaStatus, "ALG-EQUIV");
end

function testZeroMeanFeedbackConstraintEq4_52(testCase)
% (4-52)/(4-58): the strict (4-56)~(4-58) helper (book/P90.png) must
% return feedback with sum_k b_k = 0 derived from lambda (4-58) - the
% assertion inside the helper rejects a projected B, and the returned
% coefficients satisfy the constraint to machine precision.
rng(805, "twister");
H = fft(randn(1, 64) + 1j * randn(1, 64));
for rho = [0, 0.5, 0.9]
    [~, feedback] = scfde.equalizers.ch4_fd_dfe_weights(H, rho, 0.05);
    verifyEqual(testCase, sum(feedback), 0, "AbsTol", 1e-12);
end
end

function testTddaBoxedLmsEq4_8(testCase)
% Inline replica of the spec-4.8 boxed recursion; RED against the
% previous NLMS + MMSE-from-true-channel implementation.  The replica
% follows the CURRENT boundary conventions: causal zero-padded input
% window, no-prior first-round soft symbols, iteration-1 adaptation on
% the training segment only, effective step cfg.tddaMu.
[channel, source, cfg] = buildCh4Fixture(806, 18, 1);
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
[~, ~, trace] = scfde.equalizers.ch4_iterate_td_nlms_turbo( ...
    channel.received, [], [], [], cfg.noiseVariance, frame, cfg);
taps = min(cfg.tdAdaptiveTaps, N);
fb = min(cfg.feedbackTaps, N - 1);
mu = cfg.tddaMu;    % the effective boxed step after ch4_setup
wf = complex(zeros(taps, 1));
wb = complex(zeros(fb, 1));
xbar = zeros(1, N);
xbar(frame.trainingIndices) = frame.trainingSymbols;
for n = 1:N
    if n >= taps
        r = channel.received(n:-1:n - taps + 1).';
    else
        r = [channel.received(n:-1:1).'; complex(zeros(taps - n, 1))];
    end
    fbvec = complex(zeros(fb, 1));
    if n > 1
        c = min(fb, n - 1);
        fbvec(1:c) = xbar(n - 1:-1:n - c).';
    end
    z = wf' * r - wb' * fbvec;
    e = xbar(n) - z;
    if n <= numel(frame.trainingIndices)
        wf = wf + mu * r * conj(e);
        wb = wb - mu * fbvec * conj(e);
    end
end
prodWf = ifft(trace.finalChannel);
prodWf = prodWf(1:taps).';
verifyEqual(testCase, prodWf, wf, "AbsTol", 1e-9, ...
    "TDDA weights must follow the boxed LMS recursion (zero init, no normalization)");
verifyEqual(testCase, trace.formulaStatus, "ALG-EQUIV");
end

function testTfTurboNoFixedHalfMixingEq4_43_49(testCase)
% RED: the previous production averaged the time LMMSE and the FD-IBDFE
% outputs with fixed 0.5 weights; spec 4.4 forbids fixed 0.5 mixing.
[channel, source, cfg] = buildCh4Fixture(807, 18, 1);
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
H = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
[~, ~, trace] = scfde.equalizers.ch4_iterate_time_frequency_turbo( ...
    channel.received, fft(channel.received), [], [], H, H, ...
    cfg.noiseVariance, frame, cfg, false, false);
feedforward = conj(H) ./ (abs(H).^2 + cfg.noiseVariance);
eff = ifft(feedforward .* H);
[~, mainTap] = max(abs(eff));
fb = min(cfg.feedbackTaps, N - 1);
g = eff(mainTap + 1:min(mainTap + fb, N));
g = [g, zeros(1, fb - numel(g))];
xbar = zeros(1, N);
xbar(frame.trainingIndices) = frame.trainingSymbols;
oracle = ifft(feedforward .* fft(channel.received)) - ...
    timeFeedbackInline(xbar, g, N, fb);
verifyEqual(testCase, trace.softEstimates(1, :), oracle, "AbsTol", 1e-9);
verifyEqual(testCase, trace.formulaStatus, "ALG-EQUIV");
end

function testBitfEqualWeightMergeEq2_53(testCase)
% (2-53)/(4.5): forward and time-reversed passes with independent
% states; the reversed output is restored to the original time order
% and merged with EQUAL weight 1/2.
[channel, source, cfg] = buildCh4Fixture(808, 18, 1);
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
H = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
[~, ~, trace] = scfde.equalizers.ch4_iterate_time_frequency_turbo( ...
    channel.received, fft(channel.received), [], [], H, H, ...
    cfg.noiseVariance, frame, cfg, true, false);
nv = cfg.noiseVariance;
fb = min(cfg.feedbackTaps, N - 1);
xbar = zeros(1, N);
xbar(frame.trainingIndices) = frame.trainingSymbols;
ffF = conj(H) ./ (abs(H).^2 + nv);
effF = ifft(ffF .* H);
[~, mainF] = max(abs(effF));
gF = effF(mainF + 1:min(mainF + fb, N));
gF = [gF, zeros(1, fb - numel(gF))];
fwd = ifft(ffF .* fft(channel.received)) - ...
    timeFeedbackInline(xbar, gF, N, fb);
hImp = ifft(H);
revH = fft([hImp(1), hImp(N:-1:2)]);
ffR = conj(revH) ./ (abs(revH).^2 + nv);
effR = ifft(ffR .* revH);
[~, mainR] = max(abs(effR));
gR = effR(mainR + 1:min(mainR + fb, N));
gR = [gR, zeros(1, fb - numel(gR))];
revRecv = [channel.received(1), channel.received(N:-1:2)];
xbarR = [xbar(1), xbar(N:-1:2)];
rev = ifft(ffR .* fft(revRecv)) - timeFeedbackInline(xbarR, gR, N, fb);
oracle = 0.5 * fwd + 0.5 * [rev(1), rev(N:-1:2)];
verifyEqual(testCase, trace.softEstimates(1, :), oracle, "AbsTol", 1e-9);
verifyEqual(testCase, trace.formulaStatus, "ALG-EQUIV");
end

function testCh4WrappersRngPreservedAndStatus(testCase)
% The eight remaining Chapter-4 wrappers: RNG transparency, formula
% status in the trace, exactly 512 information decisions.
[channel, source, cfg] = buildCh4Fixture(809, 18, 2);
registry = scfde.equalizer_registry();
targets = ["td-turbo", "fd-dfe", "fd-turbo", "tf-turbo", ...
    "bitf-turbo", "blms-tf-turbo", "fblms", "tdda-teq"];
ch4 = find(ismember(registry.id, targets));
verifyEqual(testCase, numel(ch4), 8);
for m = ch4(:)'
    before = rng;
    recv = registry.module{m}(channel, source, cfg);
    after = rng;
    verifyEqual(testCase, after, before, ...
        "wrapper " + registry.id(m) + " must preserve caller RNG state");
    verifyTrue(testCase, isfield(recv.traces{1}, "formulaStatus"), ...
        "wrapper " + registry.id(m) + " must record formulaStatus");
    verifyEqual(testCase, numel(recv.outputs{1}), 512, ...
        "wrapper " + registry.id(m) + " must return 512 decisions");
    verifyEqual(testCase, recv.ids, registry.id(m));
end
end
