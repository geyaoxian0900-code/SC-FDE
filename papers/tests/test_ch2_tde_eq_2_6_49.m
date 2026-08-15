function tests = test_ch2_tde_eq_2_6_49
%TEST_CH2_TDE_EQ_2_6_49 Strict-formula tests for the 10 Chapter-2 TDEs
% (spec 2.1~2.10, book (2-6)~(2-49)).
%
% Independent oracles (no production helper reuse):
%   * dfe:     w = R_u^{-1} r_du with R_u/r_du accumulated inline from
%              u_k = [r(k+D..k+D-Nf+1); -d(k-1..k-Nb)]; the data phase
%              must be STATIC (no adaptation, (2-6)~(2-11));
%   * lms/nlms/rls: hand update oracles (2-14)/(2-16)/(2-23)~(2-25);
%   * dpll:    phi_k = Im{p_k(d_k+q_k)*} reconstructed from the trace
%              (RED: the old code used the opposite sign on q);
%   * mc-*:    per-element independent DPLL recursions checked symbol by
%              symbol against Im{p_p(d+q)*}; composite NLMS update norm;
%   * ptr:     (2-47) multi-element sum with per-element linear
%              convolution and per-element autocorrelation equivalent;
%   * subband: (2-48)/(2-49) P-subarray y_p streams, P*Nf+Nb post-stage,
%              per-element autocorrelation sums (no |sum h|^2 terms).

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testKnownDfeWienerSolutionEq2_8_11(testCase)
rng(601, "twister");
h = [1, 0.6 * exp(1j * 0.4), 0.25 * exp(-1j * 0.7)];
N = 64;
tx = (sign(randn(1, N)) + 1j * sign(randn(1, N))) / sqrt(2);
received = filter(h, 1, [tx, zeros(1, numel(h) - 1)]);
received = received(1:N);
cfg = struct("feedforwardTaps", 6, "feedbackTaps", 3, ...
    "trainingSymbols", 40, "modulation", "qpsk", "snrDb", 30, ...
    "noiseVariance", 1e-3);
[~, ~, ~, trace] = scfde.equalizers.known_dfe_core(received, tx, h, cfg);
verifyEqual(testCase, trace.solveMode, "training-ls-wiener");
verifyEqual(testCase, trace.adaptation, "none");
verifyEqual(testCase, trace.formulaStatus, "BOOK-EXACT");
% Independent Wiener oracle (2-8)~(2-10).
ff = cfg.feedforwardTaps;
fb = cfg.feedbackTaps;
delay = trace.decisionDelay;
trainingIdx = delay + 1:min(cfg.trainingSymbols, N);
u = complex(zeros(ff + fb, numel(trainingIdx)));
d = complex(zeros(1, numel(trainingIdx)));
for k = 1:numel(trainingIdx)
    idx = trainingIdx(k);
    oi = idx + delay;
    winStart = max(1, oi - ff + 1);
    win = received(winStart:oi);
    u(1:ff, k) = [zeros(ff - numel(win), 1); win(end:-1:1).'];
    for t = 1:min(fb, idx - 1)
        u(ff + t, k) = -tx(idx - t);
    end
    d(k) = tx(idx);
end
R = u * u' / numel(trainingIdx);
rdu = u * conj(d).' / numel(trainingIdx);
wOracle = R \ rdu;
verifyEqual(testCase, trace.finalCoefficients, wOracle, "AbsTol", 1e-9);
verifyEqual(testCase, trace.coefficientHistory(:, trace.lastProcessedSymbol), ...
    trace.finalCoefficients, "AbsTol", 0, ...
    "the last processed column must equal the final coefficients");
% Negative: the Wiener DFE is STATIC in the data phase (all processed
% data columns identical; unprocessed tail columns stay preallocated
% zeros and must not affect the result).
firstData = cfg.trainingSymbols + 1;
cols = trace.coefficientHistory(:, firstData:trace.lastProcessedSymbol);
verifyTrue(testCase, all(vecnorm(cols - cols(:, 1), 2, 1) < 1e-12), ...
    "data-phase weights must stay fixed (no adaptation in (2-6)~(2-11))");
end

function testLmsUpdateEq2_14(testCase)
% Pure update oracle for (2-14): w(n+1) = w(n) + 2mu e*(n) u(n).
rng(602, "twister");
w = randn(5, 1) + 1j * randn(5, 1);
u = randn(5, 1) + 1j * randn(5, 1);
e = 0.3 - 0.4j;
cfg = struct("lmsStep", 0.008);
[w1, ~] = scfde.equalizers.adaptive_update(w, [], u, e, cfg, "lms");
verifyEqual(testCase, w1, w + 0.008 * u * conj(e), "AbsTol", 0);
% Core-level: the per-symbol weight delta equals the boxed update with
% the composite input vector (reconstructed inline).
h = [1, 0.5];
N = 80;
rng(603, "twister");
tx = (sign(randn(1, N)) + 1j * sign(randn(1, N))) / sqrt(2);
received = filter(h, 1, [tx, zeros(1, 1)]);
received = received(1:N);
cfg2 = struct("feedforwardTaps", 4, "feedbackTaps", 2, "trainingSymbols", 30, ...
    "modulation", "qpsk", "lmsStep", 0.008, "snrDb", 25, "noiseVariance", 1e-3);
[dec, ~, est, tr] = scfde.equalizers.adaptive_dfe_core(received, tx, cfg2, "lms", false);
delay = min(ceil(4 / 3), 3);
k = 45;
uK = [received(k + 1 + delay:-1:k + 1 + delay - 3).'; -dec(k:-1:k - 1).'];
eK = dec(k + 1) - est(k + 1);
delta = tr.coefficientHistory(:, k + 1) - tr.coefficientHistory(:, k);
verifyEqual(testCase, delta, 0.008 * uK * conj(eK), "AbsTol", 1e-9);
end

function testNlmsUpdateEq2_16(testCase)
% Pure update oracle for (2-16) on ONE composite vector (feedforward
% and feedback blocks share a single normalized update).
rng(604, "twister");
w = randn(6, 1) + 1j * randn(6, 1);
u = randn(6, 1) + 1j * randn(6, 1);
e = 0.2 + 0.5j;
cfg = struct("nlmsStep", 0.35);
[w1, ~] = scfde.equalizers.adaptive_update(w, [], u, e, cfg, "nlms");
oracle = w + 0.35 * u * conj(e) / (1e-5 + real(u' * u));
verifyEqual(testCase, w1, oracle, "AbsTol", 1e-12);
% Negative: the two blocks move together as ONE composite update.
verifyEqual(testCase, norm(w1 - w), ...
    abs(0.35 * e) * norm(u) / (1e-5 + real(u' * u)), "AbsTol", 1e-12);
end

function testRlsUpdateEq2_23_25(testCase)
% Hand oracle for the boxed RLS recursion over three steps; P(0) = 100 I
% is the recorded numerical initialization.
lambda = 0.985;
cfg = struct("rlsForgettingFactor", lambda);
w = complex(zeros(4, 1));
P = 100 * eye(4);
rng(605, "twister");
U = randn(4, 3) + 1j * randn(4, 3);
E = [0.2 + 0.1j, -0.3 + 0.2j, 0.4 - 0.1j];
for step = 1:3
    u = U(:, step);
    e = E(step);
    [wA, PA] = scfde.equalizers.adaptive_update(w, P, u, e, cfg, "rls");
    gain = P * u / (lambda + real(u' * P * u));
    wO = w + gain * conj(e);
    PO = (P - gain * u' * P) / lambda;
    PO = (PO + PO') / 2;
    verifyEqual(testCase, wA, wO, "AbsTol", 1e-12);
    verifyEqual(testCase, PA, PO, "AbsTol", 1e-12);
    w = wA;
    P = PA;
end
end

function testDpllDetectorBookFormEq2_36(testCase)
% RED against the old sign: phi_k = Im{p_k(d_k+q_k)*} with q = b^H d~
% POSITIVE (trace.feedbackCancellation stores exactly q).  The loop
% recursion must match K2*phi / frequency+K1*phi symbol by symbol.
rng(606, "twister");
h = [1, 0.55 * exp(1j * 0.3), 0.2 * exp(-1j * 0.5)];
N = 120;
tx = (sign(randn(1, N)) + 1j * sign(randn(1, N))) / sqrt(2);
received = filter(h, 1, [tx, zeros(1, numel(h) - 1)]);
received = received(1:N) .* exp(1j * 0.35);
cfg = struct("feedforwardTaps", 6, "feedbackTaps", 3, "trainingSymbols", 40, ...
    "modulation", "qpsk", "nlmsStep", 0.35, "snrDb", 30, ...
    "dpllProportionalGain", 0.02, "dpllIntegralGain", 0.002);
[dec, ~, ~, tr] = scfde.equalizers.adaptive_dfe_core(received, tx, cfg, "nlms", true);
q = tr.feedbackCancellation;   % trace stores q = b^H d~ (positive form)
verifyTrue(testCase, any(abs(q) > 1e-9), ...
    "fixture must build a nonzero feedback term");
K1 = cfg.dpllProportionalGain;
K2 = cfg.dpllIntegralGain;
% The production trace stores the POST-update state at index k, so the
% recursion is verified as frequency(k)-frequency(k-1) == K2*phi(k)
% and phase(k)-phase(k-1) == frequency(k) + K1*phi(k).
for k = 40:80
    phi = imag(tr.feedforwardOutput(k) * conj(dec(k))) + ...
        imag(tr.feedforwardOutput(k) * conj(q(k)));
    verifyEqual(testCase, tr.frequency(k) - tr.frequency(k - 1), ...
        K2 * phi, "AbsTol", 1e-9);
    verifyEqual(testCase, tr.phase(k) - tr.phase(k - 1), ...
        tr.frequency(k) + K1 * phi, "AbsTol", 1e-9);
end
end

function testMcPerElementPhaseLoopsEq2_43_46(testCase)
% Per-element DPLL recursions (2-43)~(2-46) must match
% phi_p = Im{p_p(d+q)*} for EACH element, symbol by symbol, with the
% loops kept independent.
rng(607, "twister");
h1 = [1, 0.45];
h2 = [0.7 * exp(1j * 0.2), 1];
N = 120;
tx = (sign(randn(1, N)) + 1j * sign(randn(1, N))) / sqrt(2);
r1 = filter(h1, 1, [tx, zeros(1, 1)]);
r2 = filter(h2, 1, [tx, zeros(1, 1)]) .* exp(1j * 0.5);
cfg = struct("feedforwardTaps", 6, "feedbackTaps", 3, "trainingSymbols", 40, ...
    "modulation", "qpsk", "lmsStep", 0.008, "snrDb", 30, ...
    "dpllProportionalGain", 0.02, "dpllIntegralGain", 0.002);
[dec, ~, ~, tr] = scfde.equalizers.multichannel_dfe_core( ...
    [r1(1:N); r2(1:N)], tx, cfg, "lms");
K1 = cfg.dpllProportionalGain;
K2 = cfg.dpllIntegralGain;
q = tr.feedbackCancellation;   % trace stores q = b^H d~ (positive form)
verifyTrue(testCase, any(abs(q) > 1e-9), ...
    "fixture must build a nonzero feedback term");
% Post-update trace semantics: verify the recursion with the k-1
% difference for EACH element independently.
for k = 40:70
    for b = 1:2
        p = tr.branchFeedforwardOutputs(b, k);
        phi = imag(p * conj(dec(k))) + imag(p * conj(q(k)));
        verifyEqual(testCase, ...
            tr.frequencies(b, k) - tr.frequencies(b, k - 1), ...
            K2 * phi, "AbsTol", 1e-9);
        verifyEqual(testCase, tr.phases(b, k) - tr.phases(b, k - 1), ...
            tr.frequencies(b, k) + K1 * phi, "AbsTol", 1e-9);
    end
end
verifyTrue(testCase, any(abs(tr.phases(1, :) - tr.phases(2, :)) > 1e-3), ...
    "per-element phase loops must be independent");
end

function testMcNlmsCompositeUpdateEq2_45_46(testCase)
% One normalized update over the composite rotated input vector.
rng(608, "twister");
h1 = [1, 0.4];
h2 = [0.6 * exp(1j * 0.2), 1];
N = 100;
tx = (sign(randn(1, N)) + 1j * sign(randn(1, N))) / sqrt(2);
r1 = filter(h1, 1, [tx, zeros(1, 1)]);
r2 = filter(h2, 1, [tx, zeros(1, 1)]) .* exp(1j * 0.4);
cfg = struct("feedforwardTaps", 5, "feedbackTaps", 2, "trainingSymbols", 30, ...
    "modulation", "qpsk", "nlmsStep", 0.35, "snrDb", 30, ...
    "dpllProportionalGain", 0.02, "dpllIntegralGain", 0.002);
[dec, ~, est, tr] = scfde.equalizers.multichannel_dfe_core( ...
    [r1(1:N); r2(1:N)], tx, cfg, "nlms");
k = 50;
uK = tr.inputHistory(:, k + 1);
eK = dec(k + 1) - est(k + 1);
delta = tr.coefficientHistory(:, k + 1) - tr.coefficientHistory(:, k);
oracle = 0.35 * uK * conj(eK) / (1e-5 + real(uK' * uK));
verifyEqual(testCase, delta, oracle, "AbsTol", 1e-9);
end

function testPtrMultiElementSumEq2_47(testCase)
% RED: the old wrapper ignored branch 2.  The (2-47) front end must sum
% the per-element linear convolutions with per-element alignment.
h1 = [1, 0.5];
h2 = [0.5 * exp(1j * 0.3), 1];
N = 60;
rng(609, "twister");
tx = (sign(randn(1, N)) + 1j * sign(randn(1, N))) / sqrt(2);
r1 = filter(h1, 1, [tx, zeros(1, 1)]);
r2 = filter(h2, 1, [tx, zeros(1, 1)]);
ch = struct("received", r1(1:N), "impulse", h1, ...
    "branches", [r1(1:N); r2(1:N)], "branchImpulses", [h1; h2]);
src = struct("data", tx(1:40), "tx", tx, "training", tx(1:30));
cfg = struct("feedforwardTaps", 6, "feedbackTaps", 2, "trainingSymbols", 30, ...
    "modulation", "qpsk", "snrDb", 40, "noiseVariance", 1e-6);
recv = scfde.equalizers.ptr_dfe(ch, src, cfg);
y1 = conv(conj(fliplr(h1)), r1(1:N));
y1 = y1(2:2 + N - 1);
y2 = conv(conj(fliplr(h2)), r2(1:N));
y2 = y2(2:2 + N - 1);
verifyEqual(testCase, recv.estimates{1}, y1 + y2, "AbsTol", 1e-12);
verifyEqual(testCase, recv.traces{1}.ptrElementCount, 2);
verifyEqual(testCase, recv.traces{1}.formulaStatus, "BOOK-EXACT");
end

function testSubbandSubarrayStructureEq2_48_49(testCase)
% RED: the old wrapper lumped all branches into one stream and ran a
% single-branch DFE (Nf+Nb coefficients).  The strict (2-48)/(2-49)
% structure uses P subarrays with a P*Nf+Nb post-stage.
h = [1, 0.5; 0.5 * exp(1j * 0.2), 1; 1, 0.3 * exp(-1j * 0.4); 0.4, 0.9];
N = 60;
rng(610, "twister");
tx = (sign(randn(1, N)) + 1j * sign(randn(1, N))) / sqrt(2);
branches = zeros(4, N);
for b = 1:4
    rb = filter(h(b, :), 1, [tx, zeros(1, 1)]);
    branches(b, :) = rb(1:N);
end
ch = struct("received", branches(1, :), "impulse", h(1, :), ...
    "branches", branches, "branchImpulses", h);
src = struct("data", tx(1:40), "tx", tx, "training", tx(1:30));
cfg = struct("feedforwardTaps", 6, "feedbackTaps", 2, "trainingSymbols", 30, ...
    "modulation", "qpsk", "snrDb", 40, "noiseVariance", 1e-6, ...
    "numSubbands", 2, "ptrRegularization", 0.02);
recv = scfde.equalizers.subband_ptr_dfe(ch, src, cfg);
y1 = zeros(1, N);
y2 = zeros(1, N);
for b = [1, 3]
    yb = conv(conj(fliplr(h(b, :))), branches(b, :));
    y1 = y1 + yb(2:2 + N - 1);
end
for b = [2, 4]
    yb = conv(conj(fliplr(h(b, :))), branches(b, :));
    y2 = y2 + yb(2:2 + N - 1);
end
verifyEqual(testCase, recv.estimates{1}, y1 + y2, "AbsTol", 1e-12);
verifyEqual(testCase, recv.traces{1}.subarrayCount, 2);
verifyEqual(testCase, size(recv.traces{1}.coefficientHistory, 1), 14);
% Negative: equivalent channel = per-element autocorrelation sums, NOT
% |sum_k h_k|^2.
g = scfde.equalizers.subband_equivalent_channel(h(1, :), h([1, 3], :), 2);
gOracle = conv(conj(fliplr(h(1, :))), h(1, :)) + ...
    conv(conj(fliplr(h(3, :))), h(3, :));
verifyEqual(testCase, g, gOracle, "AbsTol", 1e-12);
cross = conv(conj(fliplr(h(1, :) + h(3, :))), h(1, :) + h(3, :));
verifyTrue(testCase, norm(g - cross) > 0, ...
    "equivalent channel must not be the |sum_k h_k|^2 cross-term form");
end

function testAllCh2WrappersRngPreservedAndStatus(testCase)
% Every registered Chapter-2 wrapper: RNG transparency, formula status
% in the trace, finite outputs.
rng(611, "twister");
N = 64;
imp = [1, 0.7 * exp(1j * 0.5), 0.3 * exp(-1j * 0.8), zeros(1, N - 3)];
tx = (sign(randn(1, N)) + 1j * sign(randn(1, N))) / sqrt(2);
received = ifft(fft(imp) .* fft(tx));
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received], ...
    "branchImpulses", [imp; imp]);
src = struct("data", tx(1:40), "tx", tx, "training", tx(1:32));
cfg = struct("feedforwardTaps", 6, "feedbackTaps", 3, "trainingSymbols", 32, ...
    "modulation", "qpsk", "lmsStep", 0.008, "nlmsStep", 0.35, ...
    "rlsForgettingFactor", 0.985, "rlsInitialInverseCorrelation", 100, ...
    "dpllProportionalGain", 0.02, "dpllIntegralGain", 0.002, ...
    "numSubbands", 2, "ptrRegularization", 0.02, "snrDb", 15, ...
    "noiseVariance", 10^(-15 / 10));
registry = scfde.equalizer_registry();
ch2 = find(registry.chapter == 2);
verifyEqual(testCase, numel(ch2), 10);
for m = ch2(:)'
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
