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

function testDecoderFeedbackExcludesTrainingFromBcjr(testCase)
rng(7, "twister");
training = 1 - 2 * randi([0 1], 1, 256);
information = randi([0 1], 1, 512);
coded = scfde.equalizers.ch4_convolutional_encode(information);
permutation = randperm(1024);
tx = [training, 1 - 2 * coded(permutation)];
frame = scfde.equalizers.ch4_turbo_frame_contract( ...
    struct("received", tx), ...
    struct("training", training, "data", 1 - 2 * information, "tx", tx), ...
    struct("trainingSymbols", 256, "infoBits", 512, ...
        "permutation", permutation));
llr = 50 * tx;
previous = [training, zeros(1, 1024)];
[bits, decoderFrame, softFrame] = ...
    scfde.equalizers.ch4_decoder_feedback_frame( ...
        llr, frame, previous, 1, "Log-MAP");
verifyEqual(testCase, numel(bits), 512);
verifyEqual(testCase, bits, logical(information));
verifyEqual(testCase, softFrame(frame.trainingIndices), training);
verifyEqual(testCase, decoderFrame(frame.trainingIndices), zeros(1, 256));
verifySize(testCase, decoderFrame, [1, 1280]);
verifySize(testCase, softFrame, [1, 1280]);
end

function testBasicTurboModulesReturnInformationDomain(testCase)
ids = ["td-turbo", "fd-dfe", "fd-turbo"];
for id = ids
    result = run_unified_equalizer(struct("equalizers", id, ...
        "scenario", "turbo", "frameCount", 1, ...
        "snrDb", 18, "makePlot", false, "randomSeed", 42));
    verifyEqual(testCase, numel(result.ber), 1);
    verifyEqual(testCase, result.totalBits, 512);
    verifyTrue(testCase, isfinite(result.ber) && result.ber >= 0 && result.ber <= 1);
end
end

function testBasicTurboWrappersPreserveRng(testCase)
[channel, source, cfg] = buildTurboFixture();
registry = scfde.equalizer_registry();
ids = ["td-turbo", "fd-dfe", "fd-turbo"];
for id = ids
    match = find(registry.id == id, 1);
    before = rng;
    receiver = registry.module{match}(channel, source, cfg);
    after = rng;
    verifyEqual(testCase, after, before, ...
        "Equalizer wrapper must not mutate caller RNG state");
    verifyEqual(testCase, numel(receiver.outputs{1}), 512);
end
end

function [channel, source, cfg] = buildTurboFixture()
rng(42, "twister");
information = randi([0 1], 1, 512);
coded = scfde.equalizers.ch4_convolutional_encode(information);
permutation = randperm(1024);
training = 1 - 2 * randi([0 1], 1, 256);
tx = [training, 1 - 2 * coded(permutation)];
impulse = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
H = fft([impulse, zeros(1, numel(tx) - numel(impulse))]);
noiseVariance = 10^(-18 / 10);
received = ifft(H .* fft(tx)) + sqrt(noiseVariance / 2) * ...
    (randn(size(tx)) + 1j * randn(size(tx)));
channel = struct("received", received, "impulse", impulse, ...
    "branches", [received; received]);
source = struct("training", training, "data", 1 - 2 * information, ...
    "tx", tx);
cfg = struct("noiseVariance", noiseVariance, "iterations", 3, ...
    "trainingSymbols", 256, "infoBits", 512, ...
    "permutation", permutation, "turboDecoderMode", "Log-MAP", ...
    "baselineDecoder", "Log-MAP", "turboDamping", 0.75, ...
    "tdAdaptiveTaps", 16, "tdNlmsStep", 0.35, ...
    "blmsStep", 0.2, "blmsLeakage", 1e-3, ...
    "blmsRegularization", 1e-3, "fddaStepFf", 0.2, ...
    "fddaStepFb", 0.01, "fddaBlockLength", 32, ...
    "fddaFfLength", 32, "fddaFbLength", 10);
end
