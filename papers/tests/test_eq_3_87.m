function tests = test_eq_3_87
%TEST_EQ_3_87  Book IBDFE equations (3-64)/(3-84)/(3-85)/(3-87).
%   Gamma = (1/N) sum_k A_k H_k          (3-87, contains 1/N)
%   C_k   = A_k / Gamma                  (3-84)
%   B_k   = C_k H_k - 1                  (3-85)
%   Xhat^l = (C^l)^H R - (B^l)^H Xhat^{l-1}  (3-64)
%   Unit-gain invariant: (1/N) sum_k C_k H_k = 1.
%   Includes an N=4 hand oracle and a production-path check against
%   ch3_ibdfe_equalize (trace.normalization, trace.feedback).

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testGammaHandOracleN4(testCase)
% H = [1, 2, 1+j, 0.5], A = conj(H):
%   A_k H_k = |H_k|^2 = [1, 4, 2, 0.25], sum = 7.25
%   Gamma = 7.25/4 = 1.8125
H = [1; 2; 1 + 1j; 0.5];
A = conj(H);
Gamma = (1 / numel(H)) * sum(A .* H);
verifyEqual(testCase, Gamma, 1.8125, "RelTol", 1e-12);
C = A / Gamma;
verifyEqual(testCase, C, [1; 2; 1 - 1j; 0.5] / 1.8125, "RelTol", 1e-12);
verifyEqual(testCase, (1 / numel(H)) * sum(C .* H), 1, "RelTol", 1e-12);
B = C .* H - 1;
verifyEqual(testCase, B, abs(H).^2 / 1.8125 - 1, "RelTol", 1e-12);
end

function testUnitGainInvariantRandom(testCase)
rng(31);
N = 32;
H = randn(N, 1) + 1j * randn(N, 1);
sv = 0.6;                                 % symbol variance (1-rho)
A = conj(H) .* sv ./ (abs(H).^2 .* sv + 0.1);
Gamma = (1 / N) * sum(A .* H);
C = A / Gamma;
verifyEqual(testCase, (1 / N) * sum(C .* H), 1, "RelTol", 1e-12);
end

function testProductionIbdFeTrace(testCase)
% Run the production IBDFE on an identity channel and verify the trace
% reproduces (3-84)/(3-85)/(3-87) elementwise.
rng(32);
N = 64;
dataLen = 48;
cfg = struct("fftSize", N, "dataSymbols", dataLen, "snrDb", 30, ...
    "ibdfeIterations", 2, "channelEstimateLength", 8, ...
    "channelRegularization", 0.1);
cfg = scfde.equalizers.ch3_setup(cfg, N, dataLen);
channel.impulse = [1; zeros(15, 1)];
channel.received = randn(1, N) + 1j * randn(1, N);
source.data = exp(1j * pi / 4) * (2 * randi([0 1], 1, dataLen) - 1 + ...
    1j * (2 * randi([0 1], 1, dataLen) - 1)) / sqrt(2);
uw = scfde.equalizers.ch3_zadoff_chu(cfg.uwLength, 1);
H = fft([channel.impulse(:).', zeros(1, N - numel(channel.impulse))]);
training = scfde.equalizers.ch3_zadoff_chu(N, 1);
receivedTraining = ifft(H .* fft(training)) + ...
    sqrt(cfg.noiseVariance / 2) * (randn(size(training)) + 1j * randn(size(training)));
[~, trace] = scfde.equalizers.ch3_ibdfe_equalize(channel.received, ...
    receivedTraining, training, H, cfg.noiseVariance, uw, cfg, "hard", false);
for it = 1:cfg.ibdfeIterations
    verifyEqual(testCase, abs(trace.normalization(it) - 1) < 1e-10, true);
end
% feedback = feedforward .* H - 1  (eq. 3-85) on the first iteration
verifyEqual(testCase, trace.feedback(1, :), ...
    trace.feedforward(1, :) .* H - 1, "AbsTol", 1e-12);
end
