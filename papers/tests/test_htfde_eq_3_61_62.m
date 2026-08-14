function tests = test_htfde_eq_3_61_62
%TEST_HTFDE_EQ_3_61_62  Book (3-61)/(3-62) per-element sub-array joint
% frequency-domain equalization + multichannel DPLL-DFE backend.
%
% Every expected value below is computed directly from
% STRICT_FORMULA_SPEC.md 3.3 and 2.5/2.6 inside the test body; no
% production helper participates in the oracle arithmetic:
%
%   C_{m,k}(nu) = conj(lambda)*conj(H(nu)) / (|lambda|^2*|H(nu)|^2 + sigma2)
%   x_m = IFFT{ sum_k C_{m,k} .* R_{m,k} }            (3-62)
%   p_m = a_m^H x_m e^{-j*theta_m};  p = sum_m p_m;   q = b^H d~;  z = p - q
%   phi_m = Im{ p_m (d + q)* }                        (2-36, per sub-array)
%   theta_m(n+1) = theta_m(n) + K1*phi_m(n) + K2*sum_{tau<=n} phi_m(tau)
%   K2 = 0.1*K1                                       (2-35)/(2-37)
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(papersDir);
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testEq361MatrixFormEqualsExpandedForm(testCase)
% (3-61) first line with Phi = lambda*I must equal the expanded
% |lambda|^2 / lambda* form; the wrong lambda^2/lambda form must fail.
N = 8;
H = [1; 0.5 + 0.3j; -0.2 + 0.7j; 0.4 - 0.1j; 0.9; 0.1 + 0.6j; -0.5j; 0.3];
sigma2 = 0.05;
lambda = 0.8 * exp(1j * 0.4);          % complex lambda with nonzero phase
Htilde = diag(H);
Phi = lambda * eye(N);
Denom = Htilde' * Phi' * Phi * Htilde + sigma2 * eye(N);
Cmat = Denom \ (Htilde' * Phi');        % N x N diagonal, first line of (3-61)
cMatrix = diag(Cmat);
cExpanded = conj(lambda) * conj(H) ./ ...
    (abs(lambda)^2 .* abs(H).^2 + sigma2);
verifyEqual(testCase, cMatrix, cExpanded, "AbsTol", 1e-12, ...
    "matrix form must equal the |lambda|^2 / lambda* expanded form");
% Negative: the no-conjugate lambda^2 / lambda form must differ.
cWrong = lambda * conj(H) ./ (lambda^2 .* abs(H).^2 + sigma2);
verifyNotEqual(testCase, cWrong, cExpanded, ...
    "lambda^2/lambda (no conjugate) must not equal the matrix form");
verifyGreaterThan(testCase, norm(cWrong - cExpanded), 1e-6);
% Strict degradation: lambda = 1 reduces to the per-bin MMSE form.
cLambdaOne = conj(1) * conj(H) ./ (abs(1)^2 .* abs(H).^2 + sigma2);
cOne = conj(H) ./ (abs(H).^2 + sigma2);
verifyEqual(testCase, cLambdaOne, cOne, "AbsTol", 1e-12);
end

function testTwoElementSubarrayMergeHandOracle(testCase)
% x_m = IFFT{ sum_k C_{m,k} R_{m,k} } with two independent elements,
% complex lambdas, computed entirely by hand in this test.
N = 64;
h1 = zeros(1, N); h1(1) = 1; h1(2) = 0.5 * exp(1j * 0.3); h1(4) = 0.2 * exp(-1j * 0.8);
h2 = zeros(1, N); h2(1) = 0.9 * exp(1j * 0.15); h2(3) = 0.45; h2(5) = 0.25 * exp(1j * 0.5);
tx = exp(1j * pi * (0:N-1) / 4);              % deterministic sequence
r1 = ifft(fft(h1) .* fft(tx));
r2 = ifft(fft(h2) .* fft(tx));
sigma2 = 0.01;
lam1 = 0.9 * exp(1j * 0.2);
lam2 = 0.85 * exp(-1j * 0.35);
C1 = conj(lam1) * conj(fft(h1)) ./ (abs(lam1)^2 .* abs(fft(h1)).^2 + sigma2);
C2 = conj(lam2) * conj(fft(h2)) ./ (abs(lam2)^2 .* abs(fft(h2)).^2 + sigma2);
expected = ifft(C1 .* fft(r1) + C2 .* fft(r2));
branches = [r1; r2];
branchImpulses = [h1; h2];
cfg = struct("fftSize", N, "htfdeSubarrayCount", 1, ...
    "htfdeElementsPerSubarray", 2, "htfdeElementLambdas", [lam1, lam2]);
[out, ~] = scfde.equalizers.ch3_htfde_equalize(branches, ...
    branchImpulses, sigma2, cfg);
verifyEqual(testCase, out(1, :), expected, "AbsTol", 1e-10);
end

function testElementOrderSwapDoesNotChangeMerge(testCase)
% Swapping the element order (signals, impulses and lambdas together)
% must leave the sub-array sum unchanged.
N = 32;
h1 = zeros(1, N); h1(1) = 1; h1(3) = 0.3 * exp(1j * 0.7);
h2 = zeros(1, N); h2(1) = 0.7; h2(2) = 0.4 * exp(-1j * 0.2);
tx = exp(1j * pi * (0:N-1) / 6);
r1 = ifft(fft(h1) .* fft(tx));
r2 = ifft(fft(h2) .* fft(tx));
sigma2 = 0.02;
lam1 = 0.8 * exp(1j * 0.3);
lam2 = 0.9 * exp(-1j * 0.25);
cfg = struct("fftSize", N, "htfdeSubarrayCount", 1, ...
    "htfdeElementsPerSubarray", 2, "htfdeElementLambdas", [lam1, lam2]);
[outA, ~] = scfde.equalizers.ch3_htfde_equalize([r1; r2], [h1; h2], sigma2, cfg);
cfgSwap = struct("fftSize", N, "htfdeSubarrayCount", 1, ...
    "htfdeElementsPerSubarray", 2, "htfdeElementLambdas", [lam2, lam1]);
[outB, ~] = scfde.equalizers.ch3_htfde_equalize([r2; r1], [h2; h1], sigma2, cfgSwap);
verifyEqual(testCase, outA, outB, "AbsTol", 1e-12, ...
    "element order swap must not change the merged sub-array output");
end

function testPerturbingOneElementChangesOutput(testCase)
% Changing one element's channel must change the merged output.
N = 32;
h1 = zeros(1, N); h1(1) = 1; h1(2) = 0.4;
h2 = zeros(1, N); h2(1) = 0.8; h2(3) = 0.3;
tx = exp(1j * pi * (0:N-1) / 5);
r1 = ifft(fft(h1) .* fft(tx));
r2 = ifft(fft(h2) .* fft(tx));
sigma2 = 0.02;
cfg = struct("fftSize", N, "htfdeSubarrayCount", 1, "htfdeElementsPerSubarray", 2);
[outA, ~] = scfde.equalizers.ch3_htfde_equalize([r1; r2], [h1; h2], sigma2, cfg);
h2p = h2; h2p(3) = 0.9;                          % perturb element 2
r2p = ifft(fft(h2p) .* fft(tx));
[outB, ~] = scfde.equalizers.ch3_htfde_equalize([r1; r2p], [h1; h2p], sigma2, cfg);
verifyNotEqual(testCase, outA, outB, ...
    "perturbing one element channel must change the merged output");
verifyGreaterThan(testCase, norm(outA - outB), 1e-6);
end

function testLegacyDuplicatedBranchScenarioShapeRejected(testCase)
% Negative regression: the old scenario shape (branches = [received;
% received] without per-branch impulses) must be rejected by the new
% front end; structural mismatches must raise SCFDE:ArrayStructure.
N = 32;
imp = [1, 0.4 * exp(1j * 0.3)];
tx = exp(1j * pi * (0:N-1) / 4);
r = ifft(fft(imp, N) .* fft(tx));
cfg2x1 = struct("fftSize", N, "htfdeSubarrayCount", 2, "htfdeElementsPerSubarray", 1);
% Duplicated branches without branch impulses (old scenario contract).
verifyError(testCase, @() scfde.equalizers.ch3_htfde_equalize( ...
    [r; r], imp, 0.01, cfg2x1), "SCFDE:ArrayStructure");
% M ~= P*K: three branches against P=1, K=1.
cfg1x1 = struct("fftSize", N, "htfdeSubarrayCount", 1, "htfdeElementsPerSubarray", 1);
verifyError(testCase, @() scfde.equalizers.ch3_htfde_equalize( ...
    [r; r; r], repmat(imp, 3, 1), 0.01, cfg1x1), "SCFDE:ArrayStructure");
% Branch count vs impulse count mismatch.
verifyError(testCase, @() scfde.equalizers.ch3_htfde_equalize( ...
    [r; r; r], repmat(imp, 2, 1), 0.01, cfg2x1), "SCFDE:ArrayStructure");
% Lambda vector length mismatch.
cfgBadLambda = struct("fftSize", N, "htfdeSubarrayCount", 2, ...
    "htfdeElementsPerSubarray", 1, "htfdeElementLambdas", [1, 1, 1]);
verifyError(testCase, @() scfde.equalizers.ch3_htfde_equalize( ...
    [r; r], repmat(imp, 2, 1), 0.01, cfgBadLambda), "SCFDE:ArrayStructure");
% Invalid noise variance.
verifyError(testCase, @() scfde.equalizers.ch3_htfde_equalize( ...
    [r; r], repmat(imp, 2, 1), -0.01, cfg2x1), "SCFDE:InvalidNoiseVariance");
verifyError(testCase, @() scfde.equalizers.ch3_htfde_equalize( ...
    [r; r], repmat(imp, 2, 1), 0, cfg2x1), "SCFDE:InvalidNoiseVariance");
% BOOK mode without explicit P/K must raise the parameter error.
chFull = struct("received", r, "impulse", imp);
srcFull = struct("data", tx(1:24), "tx", tx);
cfgNoPK = struct("noiseVariance", 0.01, "snrDb", 20);
verifyError(testCase, @() scfde.equalizers.htfde(chFull, srcFull, cfgNoPK), ...
    "SCFDE:BookParameterUnavailable");
end

function testSingleElementDegenerationMatchesMmseFrontEnd(testCase)
% P=1, K=1, lambda=1 must degenerate exactly to the per-bin MMSE front
% end: x = IFFT{ H* .* R ./ (|H|^2 + sigma2) }.
N = 64;
imp = zeros(1, N); imp(1) = 1; imp(2) = 0.5 * exp(1j * 0.3); imp(5) = 0.2;
tx = exp(1j * pi * (0:N-1) / 7);
r = ifft(fft(imp) .* fft(tx));
sigma2 = 0.03;
cfg = struct("fftSize", N, "htfdeSubarrayCount", 1, "htfdeElementsPerSubarray", 1);
[out, ~] = scfde.equalizers.ch3_htfde_equalize(r, imp, sigma2, cfg);
expected = ifft(conj(fft(imp)) .* fft(r) ./ (abs(fft(imp)).^2 + sigma2));
verifyEqual(testCase, out(1, :), expected, "AbsTol", 1e-10);
end

function testMultichannelDpllStepByStepOracle(testCase)
% Full symbol-by-symbol oracle of the multichannel DPLL-DFE backend with
% P=1: weights, phase error (2-36), theta recursion (2-35) and outputs
% must all match the book equations computed independently here.
N = 16;
P = 1;
x = [1.0+0.5j, -0.7+0.3j, 0.9-0.4j, 0.2+0.8j, -0.5-0.6j, 0.6+0.1j, ...
    -0.3+0.9j, 0.8-0.2j, 0.4+0.7j, -0.9+0.4j, 0.1-0.5j, 0.7+0.6j, ...
    -0.6-0.3j, 0.5+0.5j, -0.2+0.2j, 0.3-0.8j];
reference = [1+1j, 1-1j, -1+1j, -1-1j, 1+1j, -1-1j, 1-1j, -1+1j, ...
    1+1j, 1-1j, -1+1j, -1-1j, 1-1j, -1+1j, 1+1j, -1-1j] / sqrt(2);
cfg = struct("feedforwardTaps", 3, "feedbackTaps", 2, "trainingSymbols", 16, ...
    "modulation", "qpsk", "dpllProportionalGain", 0.1, "dpllIntegralGain", 0.01, ...
    "htfdeMuA", 0.05, "htfdeMuB", 0.03);
[~, ~, estimates, trace] = ...
    scfde.equalizers.multichannel_dpll_dfe_core(x, reference, cfg);
% --- independent oracle (same equations, recomputed here) ---------------
Nf = 3; Nb = 2;
delay = min(ceil(Nf / 3), Nf - 1);            % = 1 (production init)
a = zeros(Nf, 1); a(delay + 1) = 1 / P;       % production init
b = zeros(Nb, 1);
theta = 0; integral = 0;
dtilde = zeros(Nb, 1);
firstSymbol = max(Nf, Nb + delay + 1);
lastSymbol = min(numel(reference), N - delay);
phiOracle = zeros(1, N);
thetaOracle = zeros(1, N);
zOracle = zeros(1, N);
errOracle = zeros(1, N);
for n = firstSymbol:lastSymbol
    xm = x(n + delay:-1:n + delay - Nf + 1).';
    p = a' * (xm * exp(-1j * theta));
    q = b' * dtilde;
    z = p - q;
    d = reference(n);                          % all-training fixture
    e = d - z;
    a = a + 0.05 * conj(e) * (xm * exp(-1j * theta));   % (2-43)~(2-46)
    b = b - 0.03 * conj(e) * dtilde;           % minus: z = p - q
    phi = imag(p * conj(d + q));               % (2-36), not imag(e)
    integral = integral + phi;
    theta = theta + 0.1 * phi + 0.01 * integral;        % (2-35)/(2-37)
    dtilde = [d; dtilde(1:end-1)];
    phiOracle(n) = phi;
    thetaOracle(n) = theta;
    zOracle(n) = z;
    errOracle(n) = e;
end
verifyEqual(testCase, trace.phaseError(1, firstSymbol:lastSymbol), ...
    phiOracle(firstSymbol:lastSymbol), "AbsTol", 1e-12);
verifyEqual(testCase, trace.phase(1, firstSymbol:lastSymbol), ...
    thetaOracle(firstSymbol:lastSymbol), "AbsTol", 1e-12);
verifyEqual(testCase, estimates(firstSymbol:lastSymbol), ...
    zOracle(firstSymbol:lastSymbol), "AbsTol", 1e-12);
verifyEqual(testCase, trace.error(firstSymbol:lastSymbol), ...
    errOracle(firstSymbol:lastSymbol), "AbsTol", 1e-12);
% Effective parameters must be recorded in the trace metadata.
verifyEqual(testCase, trace.parameters.dpllProportionalGain, 0.1);
verifyEqual(testCase, trace.parameters.dpllIntegralGain, 0.01);
verifyEqual(testCase, trace.parameters.muA, 0.05);
verifyEqual(testCase, trace.parameters.muB, 0.03);
verifyEqual(testCase, trace.parameters.subarrayCount, P);
verifyEqual(testCase, trace.parameters.feedforwardTaps, Nf);
verifyEqual(testCase, trace.parameters.feedbackTaps, Nb);
% Negative: the phase error must not be imag(e), and must not be the old
% Im{p (d* - q)} form.
imagError = imag(conj(errOracle));
verifyNotEqual(testCase, phiOracle(firstSymbol:lastSymbol), ...
    imagError(firstSymbol:lastSymbol), "phase error must not be imag(e)");
phiOld = zeros(1, N);
thetaOld = 0; integralOld = 0; aOld = zeros(Nf, 1); aOld(delay + 1) = 1 / P;
bOld = zeros(Nb, 1); dtildeOld = zeros(Nb, 1);
for n = firstSymbol:lastSymbol
    xm = x(n + delay:-1:n + delay - Nf + 1).';
    p = aOld' * (xm * exp(-1j * thetaOld));
    q = bOld' * dtildeOld;
    z = p - q;
    d = reference(n);
    e = d - z;
    aOld = aOld + 0.05 * conj(e) * (xm * exp(-1j * thetaOld));
    bOld = bOld - 0.03 * conj(e) * dtildeOld;
    phiOld(n) = imag(p * conj(d)) - imag(p * conj(q));   % old wrong form
    integralOld = integralOld + phiOld(n);
    thetaOld = thetaOld + 0.1 * phiOld(n) + 0.01 * integralOld;
    dtildeOld = [d; dtildeOld(1:end-1)];
end
verifyNotEqual(testCase, phiOracle(firstSymbol:lastSymbol), ...
    phiOld(firstSymbol:lastSymbol), ...
    "old Im{p (d* - q)} detector must differ from book Im{p (d+q)*}");
end

function testMultichannelDpllIndependentPerSubarrayState(testCase)
% P=2: each sub-array must keep its own theta/integral state while the
% feedback branch stays common; per-sub-array phase errors follow
% phi_m = Im{ p_m (d + q)* }.
N = 12;
x1 = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j, -0.8+0.5j, 0.2-0.4j, 0.6+0.5j];
x2 = [0.5+0.6j, 0.3-0.8j, -0.7+0.1j, 0.9+0.2j, -0.3+0.4j, 0.1-0.6j, ...
    0.8+0.3j, -0.5-0.2j, 0.6-0.7j, 0.2+0.9j, -0.4+0.6j, 0.7+0.1j];
reference = [1+1j, 1-1j, -1+1j, -1-1j, 1+1j, -1-1j, 1-1j, -1+1j, ...
    1+1j, 1-1j, -1+1j, -1-1j] / sqrt(2);
cfg = struct("feedforwardTaps", 3, "feedbackTaps", 2, "trainingSymbols", 12, ...
    "modulation", "qpsk", "dpllProportionalGain", 0.1, "dpllIntegralGain", 0.01, ...
    "htfdeMuA", 0.04, "htfdeMuB", 0.02);
[~, ~, ~, trace] = ...
    scfde.equalizers.multichannel_dpll_dfe_core([x1; x2], reference, cfg);
% --- independent oracle -------------------------------------------------
Nf = 3; Nb = 2;
delay = min(ceil(Nf / 3), Nf - 1);
a1 = zeros(Nf, 1); a2 = zeros(Nf, 1);
a1(delay + 1) = 1 / 2; a2(delay + 1) = 1 / 2;
b = zeros(Nb, 1);
theta1 = 0; theta2 = 0; integral1 = 0; integral2 = 0;
dtilde = zeros(Nb, 1);
firstSymbol = max(Nf, Nb + delay + 1);
lastSymbol = min(numel(reference), N - delay);
phi1Oracle = zeros(1, N); phi2Oracle = zeros(1, N);
for n = firstSymbol:lastSymbol
    xm1 = x1(n + delay:-1:n + delay - Nf + 1).';
    xm2 = x2(n + delay:-1:n + delay - Nf + 1).';
    p1 = a1' * (xm1 * exp(-1j * theta1));
    p2 = a2' * (xm2 * exp(-1j * theta2));
    p = p1 + p2;
    q = b' * dtilde;
    z = p - q;
    d = reference(n);
    e = d - z;
    a1 = a1 + 0.04 * conj(e) * (xm1 * exp(-1j * theta1));
    a2 = a2 + 0.04 * conj(e) * (xm2 * exp(-1j * theta2));
    b = b - 0.02 * conj(e) * dtilde;
    phi1 = imag(p1 * conj(d + q));
    phi2 = imag(p2 * conj(d + q));
    integral1 = integral1 + phi1; theta1 = theta1 + 0.1 * phi1 + 0.01 * integral1;
    integral2 = integral2 + phi2; theta2 = theta2 + 0.1 * phi2 + 0.01 * integral2;
    dtilde = [d; dtilde(1:end-1)];
    phi1Oracle(n) = phi1;
    phi2Oracle(n) = phi2;
end
verifyEqual(testCase, trace.phaseError(1, firstSymbol:lastSymbol), ...
    phi1Oracle(firstSymbol:lastSymbol), "AbsTol", 1e-12);
verifyEqual(testCase, trace.phaseError(2, firstSymbol:lastSymbol), ...
    phi2Oracle(firstSymbol:lastSymbol), "AbsTol", 1e-12);
verifyNotEqual(testCase, trace.phase(1, firstSymbol:lastSymbol), ...
    trace.phase(2, firstSymbol:lastSymbol), ...
    "sub-array phase states must evolve independently");
end

function testDpllBackendBoundaries(testCase)
% First symbol (empty feedback history), training/data transition and the
% last valid symbol must all produce finite, correctly-shaped outputs.
N = 32;
training = 16;
Nf = 4; Nb = 2;
delay = min(ceil(Nf / 3), Nf - 1);            % 2 (production init)
firstSymbol = max(Nf, Nb + delay + 1);        % 5
lastSymbol = min(N, N - delay);               % 30
x = exp(1j * pi * (0:N-1) / 8);
reference = (sign(real(x)) + 1j * sign(imag(x))) / sqrt(2);
cfg = struct("feedforwardTaps", Nf, "feedbackTaps", Nb, ...
    "trainingSymbols", training, "modulation", "qpsk", ...
    "dpllProportionalGain", 0.02, "dpllIntegralGain", 0.002);
[decisions, mse, estimates, trace] = ...
    scfde.equalizers.multichannel_dpll_dfe_core(x, reference, cfg);
verifyTrue(testCase, all(isfinite(estimates)) && all(isfinite(decisions)));
verifyEqual(testCase, decisions(firstSymbol:training), ...
    reference(firstSymbol:training), ...
    "training region must use the known reference symbols");
verifyTrue(testCase, isfinite(mse(firstSymbol)), ...
    "first processed symbol (empty feedback history) must be finite");
verifyTrue(testCase, isfinite(mse(lastSymbol)), ...
    "last valid symbol must be finite");
verifyEqual(testCase, size(trace.phase), [1, N]);
verifyEqual(testCase, size(trace.phaseError), [1, N]);
end

function testModuleDoesNotTouchGlobalRng(testCase)
% The front end and the DPLL backend must be deterministic and must not
% read or advance the caller's global RNG.
N = 32;
imp = zeros(1, N); imp(1) = 1; imp(2) = 0.4;
tx = exp(1j * pi * (0:N-1) / 4);
r = ifft(fft(imp) .* fft(tx));
before = rng;
rng(12345, "twister");
seeded = rng;
cfgF = struct("fftSize", N, "htfdeSubarrayCount", 1, "htfdeElementsPerSubarray", 1);
[out1, ~] = scfde.equalizers.ch3_htfde_equalize(r, imp, 0.01, cfgF);
cfgD = struct("feedforwardTaps", 3, "feedbackTaps", 2, "trainingSymbols", 16, ...
    "modulation", "qpsk", "dpllProportionalGain", 0.02, "dpllIntegralGain", 0.002);
[~, ~, ~, tr1] = scfde.equalizers.multichannel_dpll_dfe_core(out1, tx, cfgD);
after = rng;
verifyEqual(testCase, after.State, seeded.State, "module must not advance the global RNG");
verifyEqual(testCase, after.Seed, seeded.Seed);
[out2, ~] = scfde.equalizers.ch3_htfde_equalize(r, imp, 0.01, cfgF);
[~, ~, ~, tr2] = scfde.equalizers.multichannel_dpll_dfe_core(out2, tx, cfgD);
verifyEqual(testCase, out1, out2, "AbsTol", 0, "same inputs must reproduce exactly");
verifyEqual(testCase, tr1.phase, tr2.phase, "AbsTol", 0);
rng(before);
end

function testEngineeringModeMetadata(testCase)
% Engineering smoke mode: explicit P=1, K=1 without book parameters runs
% and is marked scenarioMode="engineering", bookExperimentEquivalent=false.
N = 32;
imp = zeros(1, N); imp(1) = 1; imp(2) = 0.3;
tx = exp(1j * pi * (0:N-1) / 4);
r = ifft(fft(imp) .* fft(tx));
ch = struct("received", r, "impulse", imp);
src = struct("data", tx(1:16), "tx", tx);
cfg = struct("htfdeMode", "engineering", "noiseVariance", 0.01, "snrDb", 20, ...
    "feedforwardTaps", 4, "feedbackTaps", 2, "trainingSymbols", 16, ...
    "modulation", "qpsk");
recv = scfde.equalizers.htfde(ch, src, cfg);
verifyEqual(testCase, recv.traces{1}.scenarioMode, "engineering");
verifyEqual(testCase, recv.traces{1}.bookExperimentEquivalent, false);
verifyTrue(testCase, all(isfinite(recv.outputs{1})));
end

function testBookModeFullChainRuns(testCase)
% Book mode with explicit P/K runs the complete (3-61)/(3-62) front end
% plus multichannel DPLL-DFE and carries honest metadata.
N = 64;
dataSymbols = 48;
h1 = zeros(1, N); h1(1) = 1; h1(2) = 0.5 * exp(1j * 0.3);
h2 = zeros(1, N); h2(1) = 0.8 * exp(1j * 0.1); h2(3) = 0.35;
tx = exp(1j * pi * (0:N-1) / 4);
r1 = ifft(fft(h1) .* fft(tx));
r2 = ifft(fft(h2) .* fft(tx));
ch = struct("received", r1, "impulse", h1, "branches", [r1; r2], ...
    "branchImpulses", [h1; h2], "branchIds", ["elem1", "elem2"]);
src = struct("data", tx(1:dataSymbols), "tx", tx);
cfg = struct("htfdeMode", "book", "htfdeSubarrayCount", 2, ...
    "htfdeElementsPerSubarray", 1, "noiseVariance", 0.01, "snrDb", 20, ...
    "feedforwardTaps", 4, "feedbackTaps", 2, "trainingSymbols", 16, ...
    "modulation", "qpsk");
recv = scfde.equalizers.htfde(ch, src, cfg);
verifyEqual(testCase, recv.traces{1}.scenarioMode, "book-structure");
verifyEqual(testCase, recv.traces{1}.bookExperimentEquivalent, false);
verifyTrue(testCase, all(isfinite(recv.outputs{1})));
% Full-block output: the qpsk metric adapter then counts only the data
% region (training excluded).
verifyEqual(testCase, numel(recv.outputs{1}), N);
end
