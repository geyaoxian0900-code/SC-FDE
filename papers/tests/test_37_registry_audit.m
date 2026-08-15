function tests = test_37_registry_audit
%TEST_37_REGISTRY_AUDIT Batch-10 registry / unified-entry audit (spec
% section 10.1~10.5):
%   * 37/37 registry entries: unique IDs, valid distinct function
%     handles, existing module files, no placeholder duplicates;
%   * scenario input forms: single string / cell / string array must
%     resolve to identical ids;
%   * results metadata contract: errorBits/totalBits integers,
%     ber == errorBits ./ totalBits exactly, Clopper-Pearson bounds
%     (zero-error methods get the exact 1-(alpha/2)^(1/n) upper bound,
%     never an eps fudge), gitCommit/matlabVersion/timestamp/rngSeed/
%     scenario/equalizerId/formulaStatus present, and every method in
%     the qpsk bank records a formulaStatus (no NOT-RECORDED).

tests = functiontests({ ...
    @testRegistryModulesExistAndUniqueHandles, ...
    @testScenarioInputFormsResolveIdentically, ...
    @testResultsMetadataContract, ...
    @testZeroErrorClopperPearsonUpperBound, ...
    @testAllScenarioTracesRecordRule6Fields});
%#ok<*DEFNU>  % setupOnce is invoked by the framework, not by name
%#ok<*NASGU>  % per-iteration loop diagnostics may be unused per scenario
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testRegistryModulesExistAndUniqueHandles(testCase)
registry = scfde.equalizer_registry();
verifyEqual(testCase, numel(registry.id), 37);
verifyEqual(testCase, numel(unique(registry.id)), 37, ...
    "registry IDs must be unique");
% MATLAB's unique() does not accept function-handle cells; compare the
% resolved function names instead (no placeholder duplicates).
moduleNames = string(cellfun(@func2str, registry.module, ...
    "UniformOutput", false));
verifyEqual(testCase, numel(unique(moduleNames)), 37, ...
    "no two IDs may share one module function (no placeholder duplicates)");
for m = 1:37
    handle = registry.module{m};
    verifyTrue(testCase, isa(handle, "function_handle"), ...
        "module " + registry.id(m) + " must be a function handle");
    % functions(handle).file is empty for package function handles;
    % which(func2str(handle)) resolves every package module file.
    resolvedFile = which(func2str(handle));
    hasFile = ~isempty(resolvedFile) && exist(resolvedFile, "file") == 2;
    verifyTrue(testCase, hasFile, ...
        "module file for " + registry.id(m) + " must exist");
end
verifyEqual(testCase, sum(registry.chapter == 2), 10);
verifyEqual(testCase, sum(registry.chapter == 3), 7);
verifyEqual(testCase, sum(registry.chapter == 4), 10);
verifyEqual(testCase, sum(registry.chapter == 5), 7);
verifyEqual(testCase, sum(registry.chapter == 6), 3);
verifyEqual(testCase, sum(registry.scenario == "qpsk"), 17);
verifyEqual(testCase, sum(registry.scenario == "turbo"), 10);
verifyEqual(testCase, sum(registry.scenario == "cck"), 7);
verifyEqual(testCase, sum(registry.scenario == "csk"), 3);
end

function testScenarioInputFormsResolveIdentically(testCase)
% Single string / cell / multi-element string array inputs must resolve
% to the same ids and error counts (the string array form uses TWO ids
% so the multi-element path is actually exercised).
base = struct("scenario", "cck", "frameCount", 1, "symbols", 8, ...
    "makePlot", false, "randomSeed", 42, "snrDb", 12);
base.equalizers = {"cck-rake", "cck-dfe"};
rCell = run_unified_equalizer(base);
base.equalizers = ["cck-rake", "cck-dfe"];
rArray = run_unified_equalizer(base);
base.equalizers = "cck-rake";
rString = run_unified_equalizer(base);
verifyEqual(testCase, rCell.ids, rArray.ids);
verifyEqual(testCase, rCell.errorBits, rArray.errorBits);
verifyEqual(testCase, numel(rString.ids), 1);
verifyEqual(testCase, rString.ids, "cck-rake");
verifyEqual(testCase, rString.errorBits, rCell.errorBits(1));
end

function testResultsMetadataContract(testCase)
result = run_unified_equalizer(struct("equalizers", "all", ...
    "scenario", "qpsk", "frameCount", 1, "symbols", 8, ...
    "makePlot", false, "randomSeed", 42, "snrDb", 12));
verifyEqual(testCase, numel(result.ids), 17);
verifyTrue(testCase, all(isfinite(result.errorBits)));
verifyTrue(testCase, all(result.errorBits == round(result.errorBits)));
verifyTrue(testCase, all(result.totalBits == round(result.totalBits)));
verifyEqual(testCase, result.ber, result.errorBits ./ result.totalBits, ...
    "AbsTol", 0);
verifyTrue(testCase, all(result.ber >= result.berLower95));
verifyTrue(testCase, all(result.ber <= result.berUpper95));
verifyTrue(testCase, strlength(result.gitCommit) > 0);
verifyTrue(testCase, isstring(result.matlabVersion) || ...
    ischar(result.matlabVersion));
verifyTrue(testCase, isdatetime(result.timestamp));
verifyTrue(testCase, isfield(result, "rngSeed"));
verifyEqual(testCase, result.scenario, "qpsk");
verifyEqual(testCase, result.equalizerId, result.ids);
verifyTrue(testCase, isfield(result, "formulaStatus"));
verifyEqual(testCase, numel(result.formulaStatus), 17);
verifyTrue(testCase, all(result.formulaStatus ~= "NOT-RECORDED"), ...
    "every qpsk method must record a formulaStatus");
end

function testZeroErrorClopperPearsonUpperBound(testCase)
% At effectively noiseless SNR the zero-error methods must report the
% exact Clopper-Pearson upper bound 1 - (alpha/2)^(1/n), never an eps
% fudge.
result = run_unified_equalizer(struct("equalizers", "mmse-fde", ...
    "scenario", "qpsk", "frameCount", 1, "symbols", 8, ...
    "makePlot", false, "randomSeed", 42, "snrDb", 99));
verifyEqual(testCase, result.errorBits, 0, ...
    "fixture must be error-free at 99 dB (premise of the bound check)");
expectedUpper = 1 - (0.05 / 2)^(1 / result.totalBits);
verifyEqual(testCase, result.berUpper95, expectedUpper, "AbsTol", 1e-12);
verifyEqual(testCase, result.berLower95, 0, "AbsTol", 0);
end

function testAllScenarioTracesRecordRule6Fields(testCase)
% Rule-6 metadata contract: EVERY production trace of EVERY registered
% method (all four scenario banks) must record formulaStatus,
% formulaMode, bookExperimentEquivalent and an effectiveParameters
% struct with the expected types.
scenarios = ["qpsk", "turbo", "cck", "csk"];
expectedCounts = [17, 10, 7, 3];
for k = 1:4
    result = run_unified_equalizer(struct("equalizers", "all", ...
        "scenario", scenarios(k), "frameCount", 1, "symbols", 8, ...
        "makePlot", false, "randomSeed", 42));
    verifyEqual(testCase, numel(result.traces), expectedCounts(k), ...
        scenarios(k) + " bank must return all method traces");
    for i = 1:numel(result.traces)
        tr = result.traces{i};
        id = result.ids(i);
        verifyTrue(testCase, isfield(tr, "formulaStatus"), ...
            id + " must record formulaStatus");
        verifyTrue(testCase, isfield(tr, "formulaMode"), ...
            id + " must record formulaMode");
        verifyTrue(testCase, isfield(tr, "bookExperimentEquivalent"), ...
            id + " must record bookExperimentEquivalent");
        verifyTrue(testCase, isfield(tr, "effectiveParameters"), ...
            id + " must record effectiveParameters");
        verifyTrue(testCase, isstring(tr.formulaStatus) || ...
            ischar(tr.formulaStatus), ...
            id + " formulaStatus must be a string");
        verifyTrue(testCase, isstring(tr.formulaMode) || ...
            ischar(tr.formulaMode), ...
            id + " formulaMode must be a string");
        verifyTrue(testCase, islogical(tr.bookExperimentEquivalent) || ...
            (isnumeric(tr.bookExperimentEquivalent) && ...
            isscalar(tr.bookExperimentEquivalent)), ...
            id + " bookExperimentEquivalent must be a logical");
        verifyTrue(testCase, isstruct(tr.effectiveParameters), ...
            id + " effectiveParameters must be a struct");
    end
end
end
