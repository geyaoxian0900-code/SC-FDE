function tests = test_book_conventions
%TEST_BOOK_CONVENTIONS  Frozen project-wide conventions sanity.
%   BOOK_CONVENTIONS.md sections 1-6.  Runs inside every audit
%   (scfde.book_check_conventions) and as a standalone test file.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testDftConvention(testCase)
% X_k = sum x_n e^{-j2pi kn/N} (no 1/N); inverse has 1/N.
rng(41);
x = randn(8, 1) + 1j * randn(8, 1);
X = fft(x);
k = (0:7).';
n = 0:7;
F = exp(-1j * 2 * pi * (k * n) / 8);
verifyEqual(testCase, X, F * x, "AbsTol", 1e-12);
verifyEqual(testCase, x, ifft(X), "AbsTol", 1e-12);
verifyEqual(testCase, x, (1 / 8) * F' * X, "AbsTol", 1e-12);
end

function testNoiseVarianceConvention(testCase)
% sigma_w^2 = P_signal * 10^(-snrDb/10); E|W_k|^2 = N*sigma_w^2.
rng(42);
N = 32;
sigma2 = 10^(-12 / 10);
w = sqrt(sigma2 / 2) * (randn(N, 1) + 1j * randn(N, 1));
verifyEqual(testCase, mean(abs(w).^2), sigma2, "RelTol", 0.1);
W = fft(w);
verifyEqual(testCase, mean(abs(W).^2), N * sigma2, "RelTol", 0.1);
end

function testLlrSignConvention(testCase)
% L(b) = ln P(b=0)/P(b=1)  (0 positive, book eq. 4-2 / 4-21 / 4-22 / 4-9).
L = 2;
p0 = 1 / (1 + exp(-L));
p1 = exp(-L) / (1 + exp(-L));
verifyEqual(testCase, p0 + p1, 1, "RelTol", 1e-12);
verifyEqual(testCase, log(p0 / p1), L, "RelTol", 1e-12);
verifyEqual(testCase, double(L >= 0), 1);       % hard decision -> 0
end

function testTimeIndexConvention(testCase)
% Full linear convolution length; reverse branch (book eq. 2-50).
x = [1; 2; 3];
h = [1; 1];
verifyEqual(testCase, numel(conv(x, h)), numel(x) + numel(h) - 1);
y = [1; 2; 3; 4];
yD = y(end:-1:1);               % y_r^D(n) = y_r(N-n+1)
verifyEqual(testCase, yD, [4; 3; 2; 1]);
end
