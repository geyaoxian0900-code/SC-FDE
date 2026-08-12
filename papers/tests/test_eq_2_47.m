function tests = test_eq_2_47
%TEST_EQ_2_47  Book eq.(2-47)/(2-48): passive time reversal.
%   y(n) = h*(-n) * r(n)          (linear convolution, single branch)
%   y_p(n) = sum_k h_k*(-n) * r_k(n)   (linear convolution, subarrays)
%   Equivalent channel: Q(t) = h*(-t) * h(t).
%   Includes a 3-tap hand oracle and identity-channel alignment checks.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testLinearPtrHandOracle(testCase)
% h = [0.5, 1, 0.3], r = [1, 2, 3, 4]:
%   h*(-n) = fliplr(conj(h)) = [0.3, 1, 0.5]
%   full  = conv([0.3,1,0.5],[1,2,3,4]) = [0.3,1.6,3.4,5.2,5.5,2.0]
%   main tap of h*(-n) lands at position L = 3 (aligned with r(0)),
%   so the window is full(3:6) = [3.4,5.2,5.5,2.0]
h = [0.5, 1, 0.3];
r = [1, 2, 3, 4];
timeReversal = conj(fliplr(h));
full = conv(timeReversal, r);
L = numel(h);
y = full(L:L + numel(r) - 1);
verifyEqual(testCase, timeReversal, [0.3, 1, 0.5], "AbsTol", 1e-12);
verifyEqual(testCase, full, [0.3, 1.6, 3.4, 5.2, 5.5, 2.0], "AbsTol", 1e-12);
verifyEqual(testCase, y, [3.4, 5.2, 5.5, 2.0], "AbsTol", 1e-12);
% Equivalent channel Q = h*(-t)*h(t), main peak at position 3.
Q = conv(timeReversal, h);
verifyEqual(testCase, Q, [0.15, 0.8, 1.34, 0.8, 0.15], "AbsTol", 1e-12);
verifyEqual(testCase, max(abs(Q)), 1.34, "AbsTol", 1e-12);
end

function testIdentityChannelAlignment(testCase)
% identity h = [1, 0, ...] -> PTR output equals the input block.
h = [1, zeros(1, 5)];
r = exp(1j * pi / 4) * (2 * randi([0 1], 1, 6) - 1 + ...
    1j * (2 * randi([0 1], 1, 6) - 1)) / sqrt(2);
timeReversal = conj(fliplr(h));
full = conv(timeReversal, r);
L = numel(h);
y = full(L:L + numel(r) - 1);
verifyEqual(testCase, y, r, "AbsTol", 1e-12);
end

function testMultipathFocusing(testCase)
% Noiseless multipath: PTR output focuses the energy; with the 3-tap
% channel [0.5 1 0.3] the focused peak equals the equivalent-channel
% main tap sum(|h|^2) = 1.34.
h = [0.5, 1, 0.3];
s = [1; -1; 1; 1; -1];
r = conv(h, s).';
y = scfde.equalizers.subband_ptr(r, h, 1, 0, [], []);
verifyEqual(testCase, max(abs(y)), 1.34, "AbsTol", 1e-12);
verifyEqual(testCase, abs(y(3)), 1.34, "AbsTol", 1e-12);
verifyEqual(testCase, find(abs(y) == max(abs(y)), 1), 3);
end

function testSubbandPtrTwoBranches(testCase)
% Two branches with distinct channels: y = sum_k h_k*(-n) * r_k,
% windowed from position L_k of each branch.
h1 = [1, 0.5];
h2 = [0.5, 1];
r1 = [1, 2, 3];
r2 = [4, 5, 6];
y1 = conv(conj(fliplr(h1)), r1);   % [0.5, 2, 3.5, 3], window from L=2
y2 = conv(conj(fliplr(h2)), r2);   % [4, 7, 8.5, 3],  window from L=2
branchImpulses = [h1; h2];
branches = [r1; r2];
output = scfde.equalizers.subband_ptr(r1, h1, 1, 0, branches, branchImpulses);
expected = y1(2:4) + y2(2:4);
verifyEqual(testCase, expected, [9, 12, 6], "AbsTol", 1e-12);
verifyEqual(testCase, output, expected, "AbsTol", 1e-12);
end

function testModuleRunsFinite(testCase)
% Module-level smoke: linear PTR module returns finite outputs.
rng(0);
N = 64;
imp = [0.5; 1; 0.3; zeros(N - 3, 1)];
data = exp(1j * pi / 4) * (2 * randi([0 1], 1, 40) - 1 + ...
    1j * (2 * randi([0 1], 1, 40) - 1)) / sqrt(2);
uw = exp(1j * pi * (0:N - 41).'.^2 / (N - 40));
tx = [data, uw.'];
received = conv(imp, tx);
received = received(1:N).';
channel = struct("received", received, "impulse", imp);
source = struct("data", data, "tx", tx);
cfg = struct("snrDb", 20, "feedforwardTaps", 16, "feedbackTaps", 8, ...
    "trainingSymbols", 16, "numSubbands", 2, "ptrRegularization", 1e-3);
rec = scfde.equalizers.ptr_dfe(channel, source, cfg);
verifyTrue(testCase, all(isfinite(rec.outputs{1})));
verifyEqual(testCase, rec.ids, "ptr-dfe");
end
