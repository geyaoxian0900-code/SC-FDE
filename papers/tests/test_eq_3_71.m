function tests = test_eq_3_71
%TEST_EQ_3_71  Book MMSE frequency-domain coefficient.
%   Book form:  C_k = H_k* / (N*sigma_w^2 + M_x*|H_k|^2)
%   Production: ch3_mmse_frequency_equalize uses H*/(|H|^2 + sigma^2).
%   With m_x = 1 (unit-energy symbols), M_x = N and
%   N*sigma_w^2 + M_x*|H_k|^2 = M_x * (|H_k|^2 + sigma_w^2), so the two
%   forms differ by the positive real factor M_x = N: decision-equivalent
%   (ALG-EQUIV, BOOK_CONVENTIONS.md section 4).
%   Also verifies the lambda double-form production-path equality:
%   lambdaBook = N*sigma2/Mx == lambdaProduction = cfg.noiseVariance.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testLambdaBookEqualsProduction(testCase)
rng(21);
N = 64;
symbols = exp(1j * pi / 4) * (2 * randi([0 1], N, 1) - 1 + ...
    1j * (2 * randi([0 1], N, 1) - 1)) / sqrt(2);
snrDb = 10;
sigma2 = 10^(-snrDb / 10);          % production noiseVariance
Mx = mean(abs(fft(symbols)).^2);    % = N (m_x = 1)
lambdaBook = N * sigma2 / Mx;
verifyEqual(testCase, lambdaBook, sigma2, "RelTol", 1e-12); % == lambdaProduction
end

function testBookCoefficientHandOracle(testCase)
% N=4 hand oracle: H = [1, 2, 1+j, 0.5], sigma2 = 0.1, Mx = 4.
%   Ck_book = Hk* / (N*sigma2 + Mx*|Hk|^2) = Hk* / (4*(0.1+|Hk|^2))
H = [1; 2; 1 + 1j; 0.5];
sigma2 = 0.1;
N = 4;
Mx = N;   % unit-energy symbols
Cbook = conj(H) ./ (N * sigma2 + Mx * abs(H).^2);
expected = conj(H) ./ (4 * (0.1 + abs(H).^2));
verifyEqual(testCase, Cbook, expected, "RelTol", 1e-12);
% Production form is the positive-real multiple Mx = N of the book form:
Cprod = conj(H) ./ (abs(H).^2 + sigma2);
verifyEqual(testCase, Cbook, Cprod / N, "RelTol", 1e-12);
% Decision equivalence (QPSK): arg must be identical.
verifyEqual(testCase, angle(Cbook), angle(Cprod), "AbsTol", 1e-12);
end

function testProductionMmseMatchesBookForm(testCase)
rng(22);
N = 32;
H = randn(N, 1) + 1j * randn(N, 1);
sigma2 = 0.05;
Y = randn(N, 1) + 1j * randn(N, 1);
Xbook = Y .* conj(H) ./ (N * sigma2 + N * abs(H).^2);
Xprod = scfde.equalizers.ch3_mmse_frequency_equalize(Y, H, sigma2);
% Identical up to the positive real factor 1/N (decision-equivalent).
verifyEqual(testCase, Xbook, Xprod / N, "RelTol", 1e-12);
verifyEqual(testCase, angle(Xbook), angle(Xprod), "AbsTol", 1e-12);
end
