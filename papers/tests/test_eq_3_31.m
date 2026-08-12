function tests = test_eq_3_31
%TEST_EQ_3_31  Book eq.(3-31): circulant channel diagonalization.
%   r = H_circ s + w; with the frozen forward-DFT convention
%   F r = diag(F h) F s (no 1/N), a circulant block channel is exactly
%   diagonalized by the DFT.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testCirculantDiagonalization(testCase)
rng(81);
N = 8;
h = [0.5; 0.3; 0.1; 0; 0; 0; 0; 0];
s = randn(N, 1) + 1j * randn(N, 1);
Hc = toeplitz(h, [h(1), h(end:-1:2).']);
r = Hc * s;
Hf = fft(h);
S = fft(s);
verifyEqual(testCase, fft(r), Hf .* S, "AbsTol", 1e-12);
end
