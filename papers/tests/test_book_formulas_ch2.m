function tests = test_book_formulas_ch2
%TEST_BOOK_FORMULAS_CH2  Chapter-2 executable formula oracles.
%   eq.(2-1)/(2-2) passband model, (2-3) pulse shaping, (2-10) MSE,
%   (2-11) Wiener solution, (2-13) LMS gradient, (2-15) convergence bound.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(fileparts(mfilename("fullpath"))));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testEq22PassbandModel(testCase)
% s(t) = Re{u e^{j2 pi fc t}}; at t=0 with u=1+j -> s = 1.
t = 0;
u = 1 + 1j;
s = scfde.book_formulas.ch2_modulated_signal(t, u, 100);
verifyEqual(testCase, s, 1, "AbsTol", 1e-12);
% s_I cos - s_Q sin decomposition: u = a e^{j phi}
a = abs(u);
phi = angle(u);
s1 = scfde.book_formulas.ch2_modulated_signal(0.001, u, 100);
s2 = a * cos(2 * pi * 100 * 0.001 + phi);
verifyEqual(testCase, s1, s2, "AbsTol", 1e-12);
end

function testEq23PulseShaping(testCase)
% Rectangular pulse: u(t) at t = kT equals a(k).
a = [1, -1, 1j];
T = 1;
g = @(t) double(t >= 0 & t < T);
t = 0:0.5:2;
u = scfde.book_formulas.ch2_pulse_shaped(a, g, T, t);
verifyEqual(testCase, u(1), 1, "AbsTol", 1e-12);
verifyEqual(testCase, u(3), -1, "AbsTol", 1e-12);
verifyEqual(testCase, u(5), 1j, "AbsTol", 1e-12);
end

function testEq210_211WienerMse(testCase)
% R_u = [[2, 0.5]; [0.5, 1]], R_du = [1; 0.5], E|d|^2 = 1.
% w = R_u \ R_du; the MSE at w equals min.
Ru = [2, 0.5; 0.5, 1];
Rdu = [1; 0.5];
w = scfde.book_formulas.ch2_wiener(Ru, Rdu);
verifyEqual(testCase, w, Ru \ Rdu, "AbsTol", 1e-12);
Jmin = scfde.book_formulas.ch2_mse(w, Ru, Rdu, 1);
Jother = scfde.book_formulas.ch2_mse([0; 0], Ru, Rdu, 1);
verifyLessThan(testCase, Jmin, Jother);
% Orthogonality: gradient at w is zero
verifyEqual(testCase, Rdu - Ru * w, zeros(2, 1), "AbsTol", 1e-12);
end

function testEq213LmsGradient(testCase)
% Monte-Carlo: sample gradient approximates -2 E[e* u].
rng(61);
N = 1e5;
u = randn(N, 1) + 1j * randn(N, 1);
e = randn(N, 1) + 1j * randn(N, 1);
g = scfde.book_formulas.ch2_lms_gradient(e, u);
verifyEqual(testCase, abs(g), 0, "AbsTol", 0.05);  % uncorrelated -> ~0
end

function testEq215ConvergenceBound(testCase)
R = [2, 0.5; 0.5, 1];
lmax = scfde.book_formulas.ch2_lms_convergence_bound(R);
verifyEqual(testCase, lmax, max(eig(R)), "AbsTol", 1e-12);
% For identity R the bound is exactly 1.
verifyEqual(testCase, scfde.book_formulas.ch2_lms_convergence_bound(eye(3)), 1, ...
    "AbsTol", 1e-12);
end
