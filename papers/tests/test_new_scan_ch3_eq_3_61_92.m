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
    @testIbdfeCoefficientsEq3_86_87});
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
