function tests = test_book_formulas_ch3
%TEST_BOOK_FORMULAS_CH3  Chapter-3 executable formula oracles.
%   eq.(3-27)/(3-28) spectral efficiency, (3-37) Doppler block model,
%   (3-39)~(3-41) phase matrix approximation, (3-42)~(3-44) MMSE matrix
%   solution, (3-45)/(3-46) time-domain output and per-sample gain,
%   (3-66) correlation, (3-67) IBDFE MSE.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testEq327_28SpectralEfficiency(testCase)
[etaCp, etaUw] = scfde.book_formulas.ch3_spectral_efficiency(512, 64, 16);
verifyEqual(testCase, etaCp, 512 / 576, "RelTol", 1e-12);
verifyEqual(testCase, etaUw, 496 / 576, "RelTol", 1e-12);
verifyGreaterThan(testCase, etaCp, etaUw);
end

function testEq337DopplerBlockModel(testCase)
% r = D H s + w with D = diag(e^{j theta_k}); noiseless identity channel:
% r(k) = s(k) e^{j theta_k}.
N = 8;
theta = 2 * pi * 1e-3 * (0:N - 1);          % theta_k = 2 pi k f_s T_s
D = scfde.book_formulas.ch3_doppler_matrix(theta);
verifyEqual(testCase, D, diag(exp(1j * theta)), "AbsTol", 1e-12);
s = randn(N, 1) + 1j * randn(N, 1);
r = D * s;
verifyEqual(testCase, r, exp(1j * theta(:)) .* s, "AbsTol", 1e-12);
% (3-38) frequency-domain model: R = Phi H S (noise-free), Phi circulant.
F = exp(-1j * 2 * pi * ((0:N - 1).' * (0:N - 1)) / N);
[Phi, ~] = scfde.book_formulas.ch3_phase_approx(N, theta);
Hf = ones(N, 1);                             % identity channel
R = scfde.book_formulas.ch3_freq_model(r, F, Phi, diag(Hf), F * s);
verifyEqual(testCase, R, Phi * F * s, "AbsTol", 1e-10);
verifyEqual(testCase, R, F * r, "AbsTol", 1e-10);
end

function testEq339_341PhaseApprox(testCase)
% lambda = (1/N) sum e^{j theta_p}; Phi = F D F^H / N is circulant with
% Phi(n,n) = lambda.
N = 16;
theta = 2 * pi * 5e-4 * (0:N - 1);
[Phi, lambda] = scfde.book_formulas.ch3_phase_approx(N, theta);
verifyEqual(testCase, lambda, mean(exp(1j * theta)), "AbsTol", 1e-12);
verifyEqual(testCase, diag(Phi), lambda * ones(N, 1), "AbsTol", 1e-10);
% circulant: Phi * e_k equals a shifted version
e1 = zeros(N, 1); e1(1) = 1;
verifyEqual(testCase, Phi * e1, circshift(Phi(:, 1), 0), "AbsTol", 1e-10);
% off-diagonal magnitude small for small Doppler
off = Phi; off(1:N + 1:end) = 0;
verifyLessThan(testCase, max(abs(off(:))), 1e-2);
end

function testEq342_344MmseMatrix(testCase)
% Diagonal channel: C must equal the per-bin MMSE H*/(|H|^2 + sigma^2)
% times the Doppler rotation (Phi ~= lambda I).
N = 8;
Hf = randn(N, 1) + 1j * randn(N, 1);
sigma2 = 0.1;
theta = 2 * pi * 1e-4 * (0:N - 1);
[Phi, ~] = scfde.book_formulas.ch3_phase_approx(N, theta);
C = scfde.book_formulas.ch3_mmse_matrix(diag(Hf), Phi, sigma2);
perBin = conj(Hf) ./ (abs(Hf).^2 + sigma2);
verifyEqual(testCase, abs(C * ones(N, 1) - perBin), zeros(N, 1), "AbsTol", 1e-8);
end

function testEq345_346TimeOutput(testCase)
% Noise-free equalized output: shat = A H s, beta_k = main-tap gain;
% with C from (3-42) the mean |beta| is near 1 (unit-gain).
N = 16;
n = (0:N - 1).';
k = 0:N - 1;
F = exp(-1j * 2 * pi * (k .* n) / N);
Hf = randn(N, 1) + 1j * randn(N, 1);
sigma2 = 0.05;
theta = 2 * pi * 1e-4 * (0:N - 1);
[Phi, ~] = scfde.book_formulas.ch3_phase_approx(N, theta);
C = scfde.book_formulas.ch3_mmse_matrix(diag(Hf), Phi, sigma2);
s = randn(N, 1) + 1j * randn(N, 1);
[shat, beta] = scfde.book_formulas.ch3_time_output(F, C, Phi, diag(Hf), s);
verifyEqual(testCase, numel(shat), N);
verifyEqual(testCase, numel(beta), N);
verifyEqual(testCase, mean(abs(beta)), 1, "RelTol", 0.1);
end

function testEq366_367IbdFeStats(testCase)
rng(62);
N = 32;
x = randn(N, 1) + 1j * randn(N, 1);
xhat = x + 0.1 * (randn(N, 1) + 1j * randn(N, 1));
r = scfde.book_formulas.ch3_ibdfe_corr(fft(x), fft(xhat));
verifyEqual(testCase, abs(r - N * mean(abs(x).^2)) < 0.15 * N * mean(abs(x).^2), true);
J = scfde.book_formulas.ch3_ibdfe_mse(xhat, x);
verifyEqual(testCase, J, mean(abs(xhat - x).^2), "AbsTol", 1e-12);
end
