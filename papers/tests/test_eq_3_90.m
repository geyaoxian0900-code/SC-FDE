function tests = test_eq_3_90
%TEST_EQ_3_90  Book eq.(3-90): time-domain channel windowing.
%   h_est,k' = h_est,k' for k < L, 0 otherwise (first-L-taps noise
%   window on the estimated impulse response).

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testFirstLTapsWindow(testCase)
rng(83);
N = 32;
hest = randn(N, 1) + 1j * randn(N, 1);
L = 5;
w = hest;
w(L + 1:end) = 0;
verifyEqual(testCase, w(1:L), hest(1:L), "AbsTol", 0);
verifyEqual(testCase, w(L + 1:end), zeros(N - L, 1), "AbsTol", 0);
end
