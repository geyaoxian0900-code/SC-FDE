function tests = test_eq_4_convcode
%TEST_EQ_4_CONVCODE  Chapter-4 convolutional code (book 4.1.2).
%   Book 4.3 experiment uses (171,133)_8 (page 91-94, table 4-4);
%   the 4.5.3 FDDA experiment uses (7,5)_8 (page 111-112).
%   Verifies the parameterized encoder/trellis: default (7,5) behavior
%   is unchanged, (171,133) has constraint length 7 / 64 states, and
%   encoder output matches the trellis path output bitwise.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testDefault75Unchanged(testCase)
% Default (7,5) must reproduce the historical fixed implementation.
rng(51);
bits = randi([0 1], 1, 32);
coded = scfde.equalizers.ch4_convolutional_encode(bits);
state = [0, 0];
expected = zeros(1, 2 * numel(bits));
for index = 1:numel(bits)
    u = bits(index);
    expected(2 * index - 1) = mod(u + state(1) + state(2), 2);
    expected(2 * index) = mod(u + state(2), 2);
    state = [u, state(1)];
end
verifyEqual(testCase, coded, expected, "AbsTol", 0);
end

function test75TrellisMatchesEncoder(testCase)
[nextState, outputBits] = scfde.equalizers.ch4_convolutional_trellis([7 5]);
verifyEqual(testCase, size(nextState), [4, 2]);
% Walk the trellis for a random input and compare with the encoder.
rng(52);
bits = randi([0 1], 1, 24);
coded = scfde.equalizers.ch4_convolutional_encode(bits, [7 5]);
state = 1;
trellisCoded = zeros(1, 2 * numel(bits));
for index = 1:numel(bits)
    trellisCoded(2 * index - 1:2 * index) = ...
        outputBits(state, bits(index) + 1, :);
    state = nextState(state, bits(index) + 1);
end
verifyEqual(testCase, trellisCoded, coded, "AbsTol", 0);
end

function test171133TrellisStructure(testCase)
% (171,133)_8: constraint length 7, 64 states, generators
% 171=1111001b, 133=1011011b.
[nextState, outputBits] = scfde.equalizers.ch4_convolutional_trellis([171 133]);
verifyEqual(testCase, size(nextState), [64, 2]);
verifyEqual(testCase, size(outputBits), [64, 2, 2]);
% state 0, input 1 -> c1 = c2 = 1 (u alone in both generators: 1111001 &
% 1011011 both start with 1)
out01 = squeeze(outputBits(1, 2, :));
verifyEqual(testCase, out01(:).', [1 1], "AbsTol", 0);
end

function test171133EncoderMatchesTrellis(testCase)
rng(53);
bits = randi([0 1], 1, 40);
coded = scfde.equalizers.ch4_convolutional_encode(bits, [171 133]);
verifyEqual(testCase, numel(coded), 2 * numel(bits));
[nextState, outputBits] = scfde.equalizers.ch4_convolutional_trellis([171 133]);
state = 1;
trellisCoded = zeros(1, 2 * numel(bits));
for index = 1:numel(bits)
    trellisCoded(2 * index - 1:2 * index) = ...
        outputBits(state, bits(index) + 1, :);
    state = nextState(state, bits(index) + 1);
end
verifyEqual(testCase, trellisCoded, coded, "AbsTol", 0);
end

function testBookCodeRates(testCase)
% Both book codes are rate 1/2 (page 91-94: "编码效率为 1/2").
rng(54);
bits = randi([0 1], 1, 128);
verifyEqual(testCase, numel(scfde.equalizers.ch4_convolutional_encode(bits, [7 5])), 256);
verifyEqual(testCase, numel(scfde.equalizers.ch4_convolutional_encode(bits, [171 133])), 256);
end
