function tests = test_multielement_scenario_contract
%TEST_MULTIELEMENT_SCENARIO_CONTRACT  Multi-element qpsk scenario
% contract (batch 1 infrastructure): independent branch generation,
% per-branch impulses/ids, reference-element aliases, and the method
% reading contract (single-channel vs multichannel consumers).
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(papersDir);
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testScenarioBuildsIndependentBranches(testCase)
% The scenario must generate per-element independent signals (own noise
% draws), per-element impulse rows and element ids; the old
% branches=[received; received] duplication must be gone.
r = run_unified_equalizer(struct("equalizers", {{"dfe"}}, "scenario", "qpsk", ...
    "frameCount", 1, "elementCount", 2, "snrDb", 20, "makePlot", false, ...
    "randomSeed", 42));
lf = r.lastFrame;
verifyEqual(testCase, size(lf.branches), [2, numel(lf.tx)]);
verifyEqual(testCase, size(lf.branchImpulses), [2, numel(lf.tx)]);
verifyEqual(testCase, lf.branchIds, ["elem1", "elem2"]);
verifyGreaterThan(testCase, norm(lf.branches(1, :) - lf.branches(2, :)), 1e-9, ...
    "independent element noise must produce distinct branch signals");
verifyEqual(testCase, lf.received, lf.branches(1, :), ...
    "channel.received must be the reference element's signal");
verifyEqual(testCase, lf.impulse, lf.branchImpulses(1, :), ...
    "channel.impulse must be the reference element's impulse");
end

function testSingleChannelMethodsUseReferenceElement(testCase)
% With the same seed, element 1 draws identical noise in the M=1 and M=2
% runs; a single-channel method must therefore produce identical output,
% proving it only reads the declared reference element.
opts1 = struct("equalizers", {{"dfe"}}, "scenario", "qpsk", "frameCount", 1, ...
    "elementCount", 1, "snrDb", 20, "makePlot", false, "randomSeed", 42);
opts2 = struct("equalizers", {{"dfe"}}, "scenario", "qpsk", "frameCount", 1, ...
    "elementCount", 2, "snrDb", 20, "makePlot", false, "randomSeed", 42);
r1 = run_unified_equalizer(opts1);
r2 = run_unified_equalizer(opts2);
verifyEqual(testCase, r1.ber, r2.ber);
verifyEqual(testCase, r1.outputs{1}, r2.outputs{1}, ...
    "single-channel dfe must use only the reference element");
end

function testMultichannelMethodsConsumeAllBranches(testCase)
% A multichannel method must consume the second independent branch:
% adding a branch (same seed) must change its output.
opts1 = struct("equalizers", {{"mc-lms-dfe"}}, "scenario", "qpsk", ...
    "frameCount", 1, "elementCount", 1, "snrDb", 12, "makePlot", false, ...
    "randomSeed", 42);
opts2 = struct("equalizers", {{"mc-lms-dfe"}}, "scenario", "qpsk", ...
    "frameCount", 1, "elementCount", 2, "snrDb", 12, "makePlot", false, ...
    "randomSeed", 42);
r1 = run_unified_equalizer(opts1);
r2 = run_unified_equalizer(opts2);
verifyNotEqual(testCase, r1.outputs{1}, r2.outputs{1}, ...
    "mc-lms-dfe must consume the second independent branch");
end

function testHtfdeBookStructureThroughScenario(testCase)
% Explicit P/K drives the scenario to generate M = P*K independent
% elements and the book-structure path is exercised end to end.
r = run_unified_equalizer(struct("equalizers", {{"htfde"}}, "scenario", "qpsk", ...
    "frameCount", 1, "snrDb", 18, "makePlot", false, "randomSeed", 42, ...
    "htfdeSubarrayCount", 1, "htfdeElementsPerSubarray", 2));
verifyEqual(testCase, size(r.lastFrame.branches), [2, numel(r.lastFrame.tx)]);
verifyTrue(testCase, isfinite(r.ber) && r.ber >= 0 && r.ber <= 1);
verifyEqual(testCase, r.traces{1}.scenarioMode, "book-structure");
verifyEqual(testCase, r.traces{1}.bookExperimentEquivalent, false);
end

function testHtfdeDefaultScenarioRunsEngineeringSmoke(testCase)
% Without book P/K the scenario runs the explicit, documented engineering
% smoke structure P=1, K=1 and marks it as such.
r = run_unified_equalizer(struct("equalizers", {{"htfde"}}, "scenario", "qpsk", ...
    "frameCount", 1, "snrDb", 18, "makePlot", false, "randomSeed", 42));
verifyEqual(testCase, r.traces{1}.scenarioMode, "engineering");
verifyEqual(testCase, r.traces{1}.bookExperimentEquivalent, false);
verifyEqual(testCase, size(r.lastFrame.branches), [1, numel(r.lastFrame.tx)]);
end

function testLegacyDuplicatedBranchScenarioGone(testCase)
% The scenario must never hand duplicated rows to multichannel methods:
% with two elements the branch signals differ (independent noise).
r = run_unified_equalizer(struct("equalizers", {{"mc-lms-dfe"}}, ...
    "scenario", "qpsk", "frameCount", 1, "elementCount", 2, "snrDb", 18, ...
    "makePlot", false, "randomSeed", 42));
verifyGreaterThan(testCase, ...
    norm(r.lastFrame.branches(1, :) - r.lastFrame.branches(2, :)), 1e-9, ...
    "scenario must not duplicate one received signal as two elements");
end

function testHtfdeBerExcludesTrainingRegion(testCase)
% Entry-level negative regression for the BER region contract: the full
% 184-point backend output lets the unified metric adapter count only
% payload = trainingSymbols+1:dataSymbols, i.e. (120-64)*2 = 112 bits per
% frame.  The previous data-only 120-point output made the adapter count
% all 120 symbols (240 bits), including the 64 known training symbols.
r = run_unified_equalizer(struct("equalizers", {{"htfde"}}, "scenario", "qpsk", ...
    "frameCount", 1, "snrDb", 12, "makePlot", false, "randomSeed", 42));
verifyEqual(testCase, r.totalBits, 112, ...
    "htfde BER must exclude the 64 training symbols (per frame 112 bits)");
verifyTrue(testCase, isfinite(r.ber) && r.ber >= 0 && r.ber <= 1);
end

function testPerElementChannelsAreHonored(testCase)
% Per-element path tables must produce distinct per-element impulses
% (independent channel responses, not just independent noise).
d1 = [0, 1, 3];
g1 = [1, 0.5, 0.2];
d2 = [0, 2, 5];
g2 = [0.8, 0.4 * exp(1j * 0.5), 0.3 * exp(-1j * 0.4)];
r = run_unified_equalizer(struct("equalizers", {{"dfe"}}, "scenario", "qpsk", ...
    "frameCount", 1, "elementCount", 2, "snrDb", 20, "makePlot", false, ...
    "randomSeed", 42, "elementPathDelays", {{d1, d2}}, ...
    "elementPathGains", {{g1, g2}}));
lf = r.lastFrame;
verifyNotEqual(testCase, lf.branchImpulses(1, :), lf.branchImpulses(2, :), ...
    "per-element path tables must produce distinct per-element impulses");
verifyGreaterThan(testCase, ...
    norm(lf.branchImpulses(1, :) - lf.branchImpulses(2, :)), 1e-9);
% Effective lengths must record the last nonzero tap (delays [0,1,3] ->
% taps 1/2/4 => 4; delays [0,2,5] -> taps 1/3/6 => 6), not the padded N.
verifyEqual(testCase, lf.branchImpulseLengths, [4, 6], ...
    "branchImpulseLengths must hold the pre-padding active span");
end
