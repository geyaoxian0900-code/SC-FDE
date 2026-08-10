function tests = test_all_equalizer_runtime_contracts
%TEST_ALL_EQUALIZER_RUNTIME_CONTRACTS Focused runtime-contract tests for
% the 37-equalizer registry: Chapter-4 turbo frame contract, decoder
% feedback slicing, per-method exact statistics and the all-37 audit
% runner.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(papersDir);
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testTurboFrameContractUsesOnlyCodedData(testCase)
rng(42, "twister");
training = 1 - 2 * randi([0 1], 1, 256);
information = randi([0 1], 1, 512);
coded = scfde.equalizers.ch4_convolutional_encode(information);
permutation = randperm(1024);
tx = [training, 1 - 2 * coded(permutation)];
channel = struct("received", tx);
source = struct("training", training, "data", 1 - 2 * information, "tx", tx);
cfg = struct("trainingSymbols", 256, "infoBits", 512, ...
    "permutation", permutation);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
verifyEqual(testCase, frame.trainingIndices, 1:256);
verifyEqual(testCase, frame.dataIndices, 257:1280);
verifyEqual(testCase, frame.codedLength, 1024);
verifyEqual(testCase, frame.informationLength, 512);
verifyEqual(testCase, frame.inversePermutation(permutation), 1:1024);
end

function testTurboFrameContractRejectsFrameLengthMismatch(testCase)
channel = struct("received", ones(1, 1279));
source = struct("training", ones(1, 256), "data", ones(1, 512));
cfg = struct("trainingSymbols", 256, "infoBits", 512, ...
    "permutation", 1:1024);
verifyError(testCase, ...
    @() scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg), ...
    "SCFDE:TurboFrame");
end

function testTurboFrameContractRejectsInvalidPermutation(testCase)
channel = struct("received", ones(1, 1280));
source = struct("training", ones(1, 256), "data", ones(1, 512));
cfg = struct("trainingSymbols", 256, "infoBits", 512, ...
    "permutation", [1:1023, 1023]);
verifyError(testCase, ...
    @() scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg), ...
    "SCFDE:TurboPermutation");
end
