function tests = test_text_transmitter
%TEST_TEXT_TRANSMITTER End-to-end checks for selectable pulse shaping.

tests = functiontests(localfunctions);
end

function setupOnce(~)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "engineering_simulation"));
end

function testRrcPulseShaping(testCase)
result = run_text_scfde_demo("RRC link", ...
    struct("makePlot", false, "pulseShape", "rrc"));
verifyTrue(testCase, result.success);
verifyEqual(testCase, result.config.pulseShape, "rrc");
verifyGreaterThan(testCase, result.frames(1).syncMetric, 0.8);
verifyEqual(testCase, numel(result.frames(1).txPacketBits), 128);
verifyEqual(testCase, numel(result.frames(1).txCodeBits), 192);
verifyEqual(testCase, numel(result.frames(1).demodulation.llr), 192);
verifyEqual(testCase, numel(result.frames(1).channelImpulse), ...
    result.config.uwLength);
end

function testRectangularCompatibility(testCase)
result = run_text_scfde_demo("Rectangular link", ...
    struct("makePlot", false, "pulseShape", "rectangular"));
verifyTrue(testCase, result.success);
verifyEqual(testCase, result.config.pulseShape, "rectangular");
end
