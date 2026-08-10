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

function testAdvancedTurboModulesReturnInformationDomain(testCase)
ids = ["tf-turbo", "bitf-turbo", "blms-tf-turbo", ...
    "tdda-teq", "fdda-dfe-teq"];
for id = ids
    result = run_unified_equalizer(struct("equalizers", id, ...
        "scenario", "turbo", "frameCount", 1, ...
        "snrDb", 18, "makePlot", false, "randomSeed", 42));
    verifyEqual(testCase, result.totalBits, 512);
    verifyTrue(testCase, isfinite(result.ber) && result.ber >= 0 && result.ber <= 1);
end
end

function testAdvancedTurboWrappersPreserveRng(testCase)
[channel, source, cfg] = buildTurboFixture();
registry = scfde.equalizer_registry();
ids = ["tf-turbo", "bitf-turbo", "blms-tf-turbo", ...
    "tdda-teq", "fdda-dfe-teq"];
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

function testFblmsTurboReturnsDecodedInformation(testCase)
result = run_unified_equalizer(struct("equalizers", "fblms", ...
    "scenario", "turbo", "frameCount", 1, "snrDb", 18, ...
    "makePlot", false, "randomSeed", 42));
verifyEqual(testCase, result.totalBits, 512);
verifyTrue(testCase, result.ber >= 0 && result.ber <= 1);
trace = result.traces{1};
verifyEqual(testCase, trace.outputDomain, "information-symbols");
verifyEqual(testCase, numel(trace.equalizedFrame), 1280);
end

function testCckAndCskReturnPerMethodExactCounts(testCase)
cases = { ...
    struct("equalizers", {{"cck-rake", "cck-dfe"}}, ...
        "scenario", "cck", "symbols", 8), ...
    struct("equalizers", {{"csk-matched-filter", "csk-ese"}}, ...
        "scenario", "csk", "symbols", 8)};
for k = 1:numel(cases)
    cfg = cases{k};
    cfg.frameCount = 1;
    cfg.makePlot = false;
    cfg.randomSeed = 42;
    result = run_unified_equalizer(cfg);
    verifySize(testCase, result.ber, [1, 2]);
    verifySize(testCase, result.errorBits, [1, 2]);
    verifySize(testCase, result.totalBits, [1, 2]);
    verifyEqual(testCase, result.ber, ...
        result.errorBits ./ result.totalBits, "AbsTol", 0);
    verifyTrue(testCase, all(result.ber >= result.berLower95) && ...
        all(result.ber <= result.berUpper95));
end
end

function testCckShortFrameRaisesContractError(testCase)
verifyError(testCase, ...
    @() run_unified_equalizer(struct("equalizers", "cck-rake", ...
        "scenario", "cck", "symbols", 3, "frameCount", 1, ...
        "makePlot", false, "randomSeed", 42)), ...
    "SCFDE:FrameTooShort");
end

function testRegistryHasCompleteScenarioMetadata(testCase)
registry = scfde.equalizer_registry();
verifyEqual(testCase, numel(registry.id), 37);
verifyEqual(testCase, numel(registry.chapter), 37);
verifyEqual(testCase, numel(registry.scenario), 37);
verifyEqual(testCase, sum(registry.scenario == "qpsk"), 17);
verifyEqual(testCase, sum(registry.scenario == "turbo"), 10);
verifyEqual(testCase, sum(registry.scenario == "cck"), 7);
verifyEqual(testCase, sum(registry.scenario == "csk"), 3);
end

function testAll37EqualizersCompleteSmokeRun(testCase)
report = run_all_equalizers(struct("frameCount", 1, ...
    "snrDb", 18, "symbols", 8, "randomSeed", 42));
verifyEqual(testCase, height(report), 37);
verifyEqual(testCase, sum(report.status == "PASS"), 37, ...
    strjoin(report.message(report.status ~= "PASS"), newline));
verifyTrue(testCase, all(isfinite(report.ber)));
verifyTrue(testCase, all(report.ber >= 0 & report.ber <= 1));
verifyTrue(testCase, all(report.errorBits >= 0));
verifyTrue(testCase, all(report.totalBits > 0));
verifyTrue(testCase, all(report.ber >= report.berLower95) && ...
    all(report.ber <= report.berUpper95));
end

function testAutoRejectsMixedScenarios(testCase)
% scenario=auto must reject requests spanning multiple scenarios
% instead of guessing a priority (regression: CCK>CSK>Turbo>QPSK).
verifyError(testCase, ...
    @() run_unified_equalizer(struct("equalizers", ...
        {{"htfde", "cck-rake", "csk-ese"}}, "scenario", "auto", ...
        "frameCount", 1, "makePlot", false, "randomSeed", 42)), ...
    "SCFDE:MixedScenarios");
verifyError(testCase, ...
    @() run_unified_equalizer(struct("equalizers", ...
        {{"td-turbo", "dfe"}}, "scenario", "auto", ...
        "frameCount", 1, "makePlot", false, "randomSeed", 42)), ...
    "SCFDE:MixedScenarios");
end

function testExplicitScenarioRejectsForeignIds(testCase)
verifyError(testCase, ...
    @() run_unified_equalizer(struct("equalizers", "htfde", ...
        "scenario", "cck", "frameCount", 1, ...
        "makePlot", false, "randomSeed", 42)), ...
    "SCFDE:MixedScenarios");
end

function testAllResolvesPerScenario(testCase)
% "all" must resolve to every registered equalizer of the CURRENT
% scenario: 17 qpsk, 10 turbo, 7 cck, 3 csk.
counts = [17, 10, 7, 3];
scenarios = ["qpsk", "turbo", "cck", "csk"];
for k = 1:4
    result = run_unified_equalizer(struct("equalizers", "all", ...
        "scenario", scenarios(k), "frameCount", 1, ...
        "symbols", 8, "makePlot", false, "randomSeed", 42));
    verifyEqual(testCase, numel(result.ids), counts(k), ...
        "all in " + scenarios(k) + " must resolve to " + counts(k));
end
end

function testScenarioGroupBanksAndReproducibility(testCase)
% Whole-scenario banks must complete with exact per-method vectors;
% the same seed must reproduce exact counts, a different seed must
% change at least one error count (4 dB prevents all-zero equality).
groups = { ...
    {"dfe","lms-dfe","nlms-dfe","rls-dfe","dpll-dfe", ...
     "mc-lms-dfe","mc-nlms-dfe","mc-rls-dfe","ptr-dfe", ...
     "subband-ptr-dfe","mmse-fde","zf-fde","htfde", ...
     "sd-ibdfe","hd-ibdfe","ice-sd-ibdfe","ice-hd-ibdfe"}, ...
    {"td-turbo","fd-dfe","fd-turbo","tf-turbo","bitf-turbo", ...
     "blms-tf-turbo","fblms","tdda-teq","fdda-teq","fdda-dfe-teq"}, ...
    {"cck-rake","cck-dfe","cck-bidfe","cck-bidfe2", ...
     "cck-tr-diversity","cck-fde","cck-mfb"}, ...
    {"csk-matched-filter","csk-soft-sic","csk-ese"}};
scenarios = ["qpsk", "turbo", "cck", "csk"];
expected = [17, 10, 7, 3];
for k = 1:4
    opts = struct("equalizers", {groups{k}}, ...
        "scenario", scenarios(k), "frameCount", 1, ...
        "symbols", 8, "makePlot", false, "randomSeed", 42);
    result = run_unified_equalizer(opts);
    verifyEqual(testCase, numel(result.ber), expected(k));
    verifyEqual(testCase, size(result.ber), size(result.errorBits));
    verifyEqual(testCase, size(result.ber), size(result.totalBits));
    verifyEqual(testCase, result.ber, ...
        result.errorBits ./ result.totalBits, "AbsTol", 0);
end
% Same seed reproduces exact counts; a different seed changes errors.
opts4 = struct("equalizers", {groups{2}}, "scenario", "turbo", ...
    "frameCount", 2, "snrDb", 4, "symbols", 8, ...
    "makePlot", false, "randomSeed", 7);
rA = run_unified_equalizer(opts4);
rB = run_unified_equalizer(opts4);
opts4b = opts4; opts4b.randomSeed = 8;
rC = run_unified_equalizer(opts4b);
verifyEqual(testCase, rA.errorBits, rB.errorBits);
verifyEqual(testCase, rA.totalBits, rB.totalBits);
verifyTrue(testCase, any(rA.errorBits ~= rC.errorBits));
end

function testAllTurboWrappersPreserveRng(testCase)
% Every Chapter-4 wrapper must preserve the caller RNG state and return
% exactly 512 information decisions when called directly.
[channel, source, cfg] = buildTurboFixture();
registry = scfde.equalizer_registry();
turboIds = registry.id(registry.scenario == "turbo");
verifyEqual(testCase, numel(turboIds), 10);
for id = turboIds
    match = find(registry.id == id, 1);
    before = rng;
    receiver = registry.module{match}(channel, source, cfg);
    after = rng;
    verifyEqual(testCase, after, before, ...
        "Equalizer wrapper " + id + " must not mutate caller RNG state");
    verifyEqual(testCase, numel(receiver.outputs{1}), 512, ...
        "Equalizer " + id + " must return 512 information decisions");
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
