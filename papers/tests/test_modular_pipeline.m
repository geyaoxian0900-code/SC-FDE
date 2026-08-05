function tests = test_modular_pipeline
%TEST_MODULAR_PIPELINE Tests for default and overridden SC-TDE modules.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
addpath(fullfile(papersDir, "engineering_simulation"));
addpath(fullfile(papersDir, "examples"));
testCase.TestData.papersDir = papersDir;
end

function testDefaultPipelineReturnsReceiverMetrics(testCase)
options = small_options();
result = simulate_chapter2_single_carrier_tde(options);
verifyEqual(testCase, numel(result.names), 10);
verifyEqual(testCase, size(result.ber), [1, 10]);
verifyTrue(testCase, all(isfinite(result.ber)));
verifyEqual(testCase, numel(result.equalizerEstimates), 10);
verifyEqual(testCase, size(result.equalizerEstimates{2}), size(result.tx));
verifyEqual(testCase, numel(result.equalizerTraces), 10);
trace = result.equalizerTraces{2};
verifyEqual(testCase, size(trace.coefficientHistory, 1), ...
    options.feedforwardTaps + options.feedbackTaps);
valid = find(trace.weightNorm > 0);
verifyNotEmpty(testCase, valid);
verifyEqual(testCase, result.equalizerEstimates{2}(valid), ...
    trace.feedforwardOutput(valid) - trace.feedbackCancellation(valid), ...
    "AbsTol", 1e-12);
end

function testChannelModuleCanBeReplaced(testCase)
options = small_options();
options.modules.channel = @custom_flat_channel;
result = simulate_chapter2_single_carrier_tde(options);
verifyEqual(testCase, result.channel.impulse, exp(1j * 0.2), ...
    "AbsTol", 1e-12);
verifyEqual(testCase, size(result.ber), [1, 10]);
end

function options = small_options()
options.makePlot = false;
options.trainingSymbols = 64;
options.dataSymbols = 120;
options.feedforwardTaps = 12;
options.feedbackTaps = 6;
end
