function tests = test_eq_2_36
%TEST_EQ_2_36  Book eq.(2-36): DPLL phase detector.
%   phi_k = Im{ p_k (d_k + q_k)^* }
%   = Im{ p_k conj(d_k) } + Im{ p_k conj(q_k) }
%   p_k : feedforward output (phase-compensated), q_k : feedback output,
%   d_k : decision.  Also checks the DPLL loop removes a constant phase
%   rotation in the noiseless case (identity channel, eq. 2-35 family).

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testPhaseDetectorHandOracle(testCase)
% p = 1+j, d = 1, q = 0.5:
%   phi = Im{(1+j)(1.5)*} = Im{(1+j)*1.5} = 1.5
p = 1 + 1j;
d = 1;
q = 0.5;
phiBook = imag(p * conj(d + q));
phiSplit = imag(p * conj(d)) + imag(p * conj(q));
verifyEqual(testCase, phiBook, 1.5, "AbsTol", 1e-12);
verifyEqual(testCase, phiSplit, phiBook, "AbsTol", 1e-12);
% q must be CONJUGATED (book form) -- the old code conjugated p instead.
qImag = 0.3 + 0.4j;
verifyEqual(testCase, imag(p * conj(d + qImag)), ...
    imag(p * conj(d)) + imag(p * conj(qImag)), "AbsTol", 1e-12);
end

function testLoopConvergesToRotation(testCase)
% Miniature DPLL loop following the book recursion (eq. 2-35/2-36):
%   phi_k   = Im{ p_k (d_k + q_k)^* }
%   freq_k  = freq_{k-1} + K_I2 * phi_k
%   theta_k = theta_{k-1} + freq_k + K_P2 * phi_k
% with p_k = d_k e^{j phi_rot} e^{-j theta_{k-1}} (feedforward output
% after phase compensation) and q_k = 0 (no ISI).  The loop must drive
% theta toward phi_rot (constant rotation removal).
rng(0);
Kp = 0.05; Ki = 0.005;  % book eq.(2-37): Ki = 0.1 * Kp
phiRot = 0.6;
N = 400;
d = exp(1j * pi / 4) * (2 * randi([0 1], 1, N) - 1 + ...
    1j * (2 * randi([0 1], 1, N) - 1)) / sqrt(2);
theta = 0;
freq = 0;
phaseHistory = zeros(1, N);
for k = 1:N
    p = d(k) * exp(1j * phiRot) * exp(-1j * theta);
    q = 0;
    phi = imag(p * conj(d(k) + q));      % eq. (2-36)
    freq = freq + Ki * phi;              % integral branch
    theta = theta + freq + Kp * phi;     % eq. (2-35) accumulator
    phaseHistory(k) = theta;
end
verifyEqual(testCase, phaseHistory(end), phiRot, "AbsTol", 0.05, ...
    "DPLL loop must converge to the constant rotation");
% residual phase error must be small -> decisions correct
verifyEqual(testCase, all(phaseHistory(end - 50:end) > phiRot - 0.05), true);
end

