function tests = test_book_formulas_ch6
%TEST_BOOK_FORMULAS_CH6  Chapter-6 executable formula oracles.
%   eq.(6-2)/(6-3) spreading rates, (6-4)/(6-5) shift matrix and
%   orthogonality, (6-7) CSK correlation detector, (6-38) PTR equivalent
%   channel, (6-41)/(6-42) PTR-ESE observation moments.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testEq62_63Rates(testCase)
% L=256, T_c=0.25 ms -> R_DSSS = 1/(256*2.5e-4) = 15.625 symbols/s
[rD, rM] = scfde.book_formulas.ch6_spreading_rate(256, 2.5e-4, 4);
verifyEqual(testCase, rD, 1 / (256 * 2.5e-4), "RelTol", 1e-12);
verifyEqual(testCase, rM, 2 / (256 * 2.5e-4), "RelTol", 1e-12);
end

function testEq64_65ShiftOrthogonality(testCase)
% Shift matrix structure (6-4): T e_1 = e_M, T^M = I.
% Orthogonality (6-5): for a +/-1 m-sequence, c^T T^m c = M if
% m mod M == 0 and -1 otherwise, i.e. |c^T T^m c| = 1 for m ~= 0.
% (Book prints 1; the m-sequence gives -1 -- OCR-UNCERTAIN, see trace.)
M = 7;
c = [1; 1; 1; -1; 1; -1; -1];               % m-sequence (x^3+x^2+1)
[T, corr] = scfde.book_formulas.ch6_shift_matrix(c, 0:M - 1);
verifyEqual(testCase, T * [1; zeros(M - 1, 1)], [zeros(1, 1); 1; zeros(M - 2, 1)], ...
    "AbsTol", 1e-12);   % T e_1 = e_2 (book eq. 6-4)
verifyEqual(testCase, T ^ M, eye(M), "AbsTol", 1e-12);
verifyEqual(testCase, corr(1), M, "RelTol", 1e-12);
verifyEqual(testCase, abs(corr(2:end)), ones(1, M - 1), "RelTol", 1e-12);
end

function testEq67CorrelationDetector(testCase)
% a = ZC sequence; received o = a (no noise, no shift): the correlation
% detector peaks at lag 0 with value ~M/G (real part).
M = 16;
a = exp(1j * pi * (0:M - 1).' / M);
o = a;
ahat = scfde.book_formulas.ch6_csk_correlate(o, a, M);
[peak, at] = max(ahat);
verifyEqual(testCase, at, 1, "AbsTol", 1e-12);
verifyEqual(testCase, peak, 1, "RelTol", 1e-10);   % 1/G * M = 1 (unit energy)
% A shifted receive produces a peak at the shift lag.
oShift = a(mod((0:M - 1).' - 3, M) + 1);
ahatS = scfde.book_formulas.ch6_csk_correlate(oShift, a, M);
[~, atS] = max(ahatS);
verifyEqual(testCase, atS, 4, "AbsTol", 1e-12);
end

function testEq638PtrEquivalentChannel(testCase)
% Q = h * bhat*(-n) (linear convolution); for bhat = h the main tap
% equals sum |h|^2.
h = [0.5, 1, 0.3];
Q = scfde.book_formulas.ch6_ptr_equivalent_channel(h, h);
verifyEqual(testCase, Q(:), conv(h(:), conj(flipud(h(:)))), "AbsTol", 1e-12);
verifyEqual(testCase, max(abs(Q)), sum(abs(h).^2), "AbsTol", 1e-12);
end

function testEq610_612ShiftEstimate(testCase)
% (6-10)/(6-12): correlation peak -> shift index estimate.
ahat = [0.1, 0.05, 0.9, 0.2];
[~, deltaHat] = scfde.book_formulas.ch6_shift_estimate(ahat, [], 4);
verifyEqual(testCase, deltaHat, 3, "AbsTol", 1e-12);
end

function testEq641_642Moments(testCase)
% Two users, one tap each: Q = [1 0.5; 0.5 1], muX = [0.8; 0.6],
% varX = [0.3; 0.4], hhat = [1 0.5], sigma2 = 0.1.
Q = [1, 0.5; 0.5, 1];
muX = [0.8; 0.6];
varX = [0.3; 0.4];
hhat = [1, 0.5];
sigma2 = 0.1;
[meanY, varY] = scfde.book_formulas.ch6_ptr_ese_moments(Q, muX, varX, hhat, sigma2);
verifyEqual(testCase, meanY, 0.8 * 1.5 + 0.6 * 1.5, "AbsTol", 1e-12);
verifyEqual(testCase, varY, 0.3 * 1.25 + 0.4 * 1.25 + 1.25 * 0.1, ...
    "AbsTol", 1e-12);
end
