function tests = test_eq_3_65
%TEST_EQ_3_65  Book eq.(3-65): M_Xk = E|X_k|^2, M_Xhat,k = E|Xhat_k|^2.
%   Verifies the frozen Parseval convention M_x = N * m_x
%   (BOOK_CONVENTIONS.md section 2) with an N=4 hand oracle.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testParsevalN4HandOracle(testCase)
% x = [1; 2; 3; 4], N = 4:
%   m_x = (1+4+9+16)/4 = 30/4 = 7.5
%   X   = [10; -2+2j; -2; -2-2j]
%   M_x = (100 + 8 + 4 + 8)/4 = 120/4 = 30 = N * m_x
x = [1; 2; 3; 4];
mx = mean(abs(x).^2);
X = fft(x);
Mx = mean(abs(X).^2);
verifyEqual(testCase, mx, 7.5, "RelTol", 1e-12);
verifyEqual(testCase, Mx, 30, "RelTol", 1e-12);
verifyEqual(testCase, Mx, 4 * mx, "RelTol", 1e-12);
end

function testParsevalRandomBlock(testCase)
rng(11);
N = 64;
x = randn(N, 1) + 1j * randn(N, 1);
X = fft(x);
verifyEqual(testCase, mean(abs(X).^2), N * mean(abs(x).^2), ...
    "RelTol", 1e-12);
end

function testUnitEnergySymbolsGiveMxN(testCase)
% Unit-energy QPSK symbols: m_x = 1 -> M_x = N.
rng(12);
N = 32;
x = exp(1j * pi / 4) * (2 * randi([0 1], N, 1) - 1 + ...
    1j * (2 * randi([0 1], N, 1) - 1)) / sqrt(2);
verifyEqual(testCase, mean(abs(x).^2), 1, "RelTol", 1e-12);
verifyEqual(testCase, mean(abs(fft(x)).^2), N, "RelTol", 1e-12);
end

function testLambdaFormsAgree(testCase)
% lambda = N*sigma_w^2/M_x = sigma_w^2/m_x  (BOOK_CONVENTIONS section 4)
rng(13);
N = 128;
x = exp(1j * pi / 4) * (2 * randi([0 1], N, 1) - 1 + ...
    1j * (2 * randi([0 1], N, 1) - 1)) / sqrt(2);
sigma2 = 10^(-8 / 10);
Mx = mean(abs(fft(x)).^2);
lambdaBook = N * sigma2 / Mx;
lambdaTime = sigma2 / mean(abs(x).^2);
verifyEqual(testCase, lambdaBook, lambdaTime, "RelTol", 1e-12);
verifyEqual(testCase, lambdaBook, sigma2, "RelTol", 1e-12); % m_x = 1
end
