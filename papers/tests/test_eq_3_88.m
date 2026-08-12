function tests = test_eq_3_88
%TEST_EQ_3_88  Book eq.(3-88): LS channel estimate.
%   H_LS' = R / X_D^0 = H + W / X_D^0 = H + e'
%   (frequency-domain pointwise division by the known pilot spectrum).

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testLsEstimateEqualsChannelPlusError(testCase)
rng(82);
N = 16;
H = randn(N, 1) + 1j * randn(N, 1);
X = randn(N, 1) + 1j * randn(N, 1);      % known pilot spectrum
W = (randn(N, 1) + 1j * randn(N, 1)) * 0.05;
R = X .* H + W;
Hls = R ./ X;
verifyEqual(testCase, Hls, H + W ./ X, "AbsTol", 1e-12);
verifyEqual(testCase, Hls - H, W ./ X, "AbsTol", 1e-12);   % e' = W/X
end
