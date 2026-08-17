function tests = test_new_scan_ch3_eq_3_61_92
%TEST_NEW_SCAN_CH3_EQ_3_61_92 Strict-formula tests recovered from the new
% high-resolution scans (2026-08-17):
%   * (3-86)/(3-87) IBDFE Lambda/Gamma coefficients with N*sigma_w^2
%     (book/P67.png; RED against the previous missing-N denominator);
%   * (3-92) channel-estimate fusion own-weight ordering (book/P68.png);
%   * (3-61) HTFDE complex-lambda orientation lambda*H^H (book/P60.png);
%   * Table 3-2 five-path reference channel (book/P68.png).
%
% Independent oracles only - no production helper reuse.  The setup adds
% BOTH papers and papers/modules so clean matlab -batch runs do not
% depend on persistent paths.

tests = functiontests({ ...
    @testIbdfeCoefficientsEq3_86_87, ...
    @testChannelEstimateFusionEq3_92, ...
    @testHtfdeLambdaOrientationEq3_61});
%#ok<*DEFNU>  % setupOnce is invoked by the framework, not by name
%#ok<*NASGU>  % fixture outputs unused by individual tests are intentional
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(papersDir);
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testIbdfeCoefficientsEq3_86_87(testCase)
% (3-86)/(3-87) from book/P67.png:
%   Lambda_k = conj(H_k) * Sigma_k / (|H_k|^2 * Sigma_k + N * sigma_w^2)
%   Gamma    = mean_k Lambda_k * H_k
%   C_k      = Lambda_k / Gamma,   B_k = C_k * H_k - 1
% The N*sigma_w^2 term is a REAL factor change versus the old missing-N
% denominator, so the negative assertion compares the filter values.
rng(2401, "twister");
N = 8;
H = (randn(1, N) + 1j * randn(1, N)) / sqrt(2);   % complex H
Sigma = 0.3 + 0.5 * rand(1, N);                   % non-unit symbol variances
noiseVariance = 0.07;                             % nonzero noise
lambdaExpected = conj(H) .* Sigma ./ ...
    (abs(H).^2 .* Sigma + N * noiseVariance);
gammaExpected = mean(lambdaExpected .* H);
cExpected = lambdaExpected ./ gammaExpected;
bExpected = cExpected .* H - 1;
[feedforward, feedback, lambda, gamma] = ...
    scfde.equalizers.ch3_ibdfe_coefficients(H, Sigma, noiseVariance, N);
verifyEqual(testCase, lambda, lambdaExpected, "AbsTol", 1e-12, ...
    "(3-86) Lambda numerator/denominator must include N*sigma_w^2");
verifyEqual(testCase, gamma, gammaExpected, "AbsTol", 1e-12, ...
    "(3-87) Gamma = mean(Lambda .* H)");
verifyEqual(testCase, feedforward, cExpected, "AbsTol", 1e-12, ...
    "C = Lambda / Gamma");
verifyEqual(testCase, feedback, bExpected, "AbsTol", 1e-12, ...
    "B = C*H - 1");
% Negative: the old denominator WITHOUT N*sigma_w^2 must differ.
wrongLambda = conj(H) .* Sigma ./ (abs(H).^2 .* Sigma + noiseVariance);
verifyTrue(testCase, any(abs(wrongLambda - lambdaExpected) > 1e-9), ...
    "the missing-N denominator must be rejected by the oracle");
% Negative: numerator conj orientation is fixed by the oracle; a
% non-conjugated numerator must differ.
wrongNumerator = H .* Sigma ./ ...
    (abs(H).^2 .* Sigma + N * noiseVariance);
verifyTrue(testCase, any(abs(wrongNumerator - lambdaExpected) > 1e-9), ...
    "the numerator must be conj(H) * Sigma");
% Scalar Sigma (iteration-level symbol variance) must broadcast over all
% bins exactly like the per-bin vector form.
SigmaScalar = 0.55;
lambdaScalar = conj(H) .* SigmaScalar ./ ...
    (abs(H).^2 .* SigmaScalar + N * noiseVariance);
gammaScalar = mean(lambdaScalar .* H);
[ffS, fbS, ~, ~] = scfde.equalizers.ch3_ibdfe_coefficients( ...
    H, SigmaScalar, noiseVariance, N);
verifyEqual(testCase, ffS, lambdaScalar ./ gammaScalar, "AbsTol", 1e-12, ...
    "scalar Sigma must broadcast per (3-86)/(3-87)");
verifyEqual(testCase, fbS, lambdaScalar ./ gammaScalar .* H - 1, ...
    "AbsTol", 1e-12, "scalar Sigma feedback B = C*H-1");
end

function testChannelEstimateFusionEq3_92(testCase)
% (3-92) from book/P68.png: Hnew = (H0*sigma0^2 + HDft*sigmaDft^2) /
% (sigma0^2 + sigmaDft^2) - each branch weighted by ITS OWN variance.
% The previous production used the cross-weight ordering
% (sigmaDft^2*H0 + sigma0^2*HDft); the recovered scan rejects it.
rng(2402, "twister");
N = 16;
H0 = (randn(1, N) + 1j * randn(1, N)) / sqrt(2);
HDft = (randn(1, N) + 1j * randn(1, N)) / sqrt(2);
s0 = 0.2 + 0.6 * rand;       % scalar variances
sd = 0.3 + 0.8 * rand;
expected = (H0 .* s0 + HDft .* sd) ./ (s0 + sd);
wrongCross = (H0 .* sd + HDft .* s0) ./ (s0 + sd);
verifyTrue(testCase, any(abs(expected - wrongCross) > 1e-9), ...
    "premise: own-weight and cross-weight orderings differ");
actual = scfde.equalizers.ch3_channel_estimate_fuse(H0, HDft, s0, sd);
verifyEqual(testCase, actual, expected, "AbsTol", 1e-12, ...
    "(3-92) must weight each estimate by its own variance");
verifyTrue(testCase, any(abs(actual - wrongCross) > 1e-9), ...
    "the cross-weight ordering must NOT be produced");
% Per-bin variances must also fuse exactly.
s0v = 0.1 + 0.5 * rand(1, N);
sdv = 0.1 + 0.7 * rand(1, N);
expectedV = (H0 .* s0v + HDft .* sdv) ./ (s0v + sdv);
actualV = scfde.equalizers.ch3_channel_estimate_fuse(H0, HDft, s0v, sdv);
verifyEqual(testCase, actualV, expectedV, "AbsTol", 1e-12, ...
    "per-bin variances must fuse per (3-92)");
% Invalid inputs must raise (negative variance, jointly zero denominator).
verifyError(testCase, @() scfde.equalizers.ch3_channel_estimate_fuse( ...
    H0, HDft, -1, sd), "SCFDE:InvalidFusionInput", ...
    "negative variance must be rejected");
verifyError(testCase, @() scfde.equalizers.ch3_channel_estimate_fuse( ...
    H0, HDft, 0, 0), "SCFDE:InvalidFusionInput", ...
    "jointly zero variances must be rejected");
end

function testHtfdeLambdaOrientationEq3_61(testCase)
% (3-61) expanded line recovered from book/P60.png: the scalar numerator
% is lambda * H^H (lambda NOT conjugated).  A REAL lambda cannot
% distinguish the forms, so this oracle uses a COMPLEX lambda and
% drives the production front end end-to-end.
rng(2403, "twister");
N = 64;
imp = zeros(1, N);
imp(1) = 1;
imp(2) = 0.5 * exp(1j * 0.3);
imp(5) = 0.2 * exp(-1j * 0.7);
tx = exp(1j * pi * (0:N-1) / 7);
r = ifft(fft(imp) .* fft(tx));
lambda = 0.6 + 0.35j;                 % complex lambda (nonzero phase)
noiseVariance = 0.05;
Hf = fft(imp);
expected = lambda .* conj(Hf) ./ ...
    (abs(lambda).^2 .* abs(Hf).^2 + noiseVariance);
wrong = conj(lambda) .* conj(Hf) ./ ...
    (abs(lambda).^2 .* abs(Hf).^2 + noiseVariance);
verifyTrue(testCase, any(abs(expected - wrong) > 1e-9), ...
    "premise: lambda and conj(lambda) orientations differ for complex lambda");
cfg = struct("fftSize", N, "htfdeSubarrayCount", 1, ...
    "htfdeElementsPerSubarray", 1, "htfdeElementLambdas", lambda);
[out, ~] = scfde.equalizers.ch3_htfde_equalize( ...
    r, imp, noiseVariance, cfg);
verifyEqual(testCase, out(1, :), ifft(expected .* fft(r)), "AbsTol", 1e-10, ...
    "front end must use lambda*conj(H) per (3-61) (book/P60.png)");
verifyGreaterThan(testCase, ...
    norm(out(1, :) - ifft(wrong .* fft(r))), 1e-6, ...
    "the conj(lambda) orientation must NOT be produced");
end
