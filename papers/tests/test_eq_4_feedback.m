function tests = test_eq_4_feedback
%TEST_EQ_4_FEEDBACK  Book feedback lock for chapter-4 turbo equalizers.
%   The book defines no soft-feedback damping (feedback uses decoder
%   soft symbols directly, eq. 4-47/4-49), so ch4_setup locks
%   cfg.turboDamping = 1 by default.  With alpha = 1 the rebuilt soft
%   frame equals the decoder candidate tanh(posterior/2) and is
%   independent of the previous frame; training positions stay locked.

tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testBookDefaultIsUndamped(testCase)
% ch4_setup must lock turboDamping = 1 (no damping in the book).
cfg = scfde.equalizers.ch4_setup(struct(), 1280);
verifyEqual(testCase, cfg.turboDamping, 1, "AbsTol", 1e-12);
% an explicit engineering override is still honored
cfg2 = scfde.equalizers.ch4_setup(struct("turboDamping", 0.75), 1280);
verifyEqual(testCase, cfg2.turboDamping, 0.75, "AbsTol", 1e-12);
end

function frame = make_frame()
% Build a valid chapter-4 turbo frame through the contract function.
trainingLength = 256;
infoLength = 512;
codedLength = 2 * infoLength;
rng(7);
perm = randperm(codedLength);
informationSymbols = 2 * (randi([0 1], 1, infoLength) - 0.5) * 2;
informationSymbols(informationSymbols == 0) = 1;
informationSymbols = sign(informationSymbols);
training = exp(1j * pi * (0:trainingLength - 1) .^ 2 / trainingLength);
cfg = struct("trainingSymbols", trainingLength, "infoBits", infoLength, ...
    "permutation", perm);
channel = struct("received", ...
    [training, zeros(1, codedLength)] + 0 * 1j);
source = struct("data", informationSymbols, "training", training);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
end

function testAlphaOneFeedbackEqualsCandidate(testCase)
% With damping = 1 the data soft frame must equal the candidate
% tanh(posterior/2) and be independent of the previous frame.
rng(71);
frame = make_frame();
frame.informationBits = logical(randi([0 1], 1, frame.informationLength));
coded = scfde.equalizers.ch4_convolutional_encode( ...
    double(frame.informationBits), [7 5]);
frame.coded = coded;
equalizerLlr = randn(1, frame.frameLength);
previousA = randn(1, frame.frameLength);
previousB = randn(1, frame.frameLength) * 100;
[~, ~, softA] = scfde.equalizers.ch4_decoder_feedback_frame( ...
    equalizerLlr, frame, previousA, 1, "Log-MAP");
[~, ~, softB] = scfde.equalizers.ch4_decoder_feedback_frame( ...
    equalizerLlr, frame, previousB, 1, "Log-MAP");
% independent of previous frame on the data positions
verifyEqual(testCase, softA(frame.dataIndices), ...
    softB(frame.dataIndices), "AbsTol", 1e-12);
% equals tanh(posterior/2): rebuild via the same BCJR path
[~, ~, ~, ~, codedLlr] = scfde.equalizers.ch4_decoder_feedback_frame( ...
    equalizerLlr, frame, previousA, 1, "Log-MAP");
posteriorTx = codedLlr(frame.permutation);
candidate = tanh(posteriorTx / 2);
verifyEqual(testCase, softA(frame.dataIndices), candidate, "AbsTol", 1e-12);
% training positions locked to the known training symbols
verifyEqual(testCase, softA(frame.trainingIndices), ...
    frame.trainingSymbols, "AbsTol", 1e-12);
end

function testAlphaZeroKeepsPrevious(testCase)
% damping = 0 keeps the previous soft frame (boundary behavior).
rng(72);
frame = make_frame();
frame.informationBits = logical(randi([0 1], 1, frame.informationLength));
frame.coded = scfde.equalizers.ch4_convolutional_encode( ...
    double(frame.informationBits), [7 5]);
previous = randn(1, frame.frameLength);
[~, ~, soft] = scfde.equalizers.ch4_decoder_feedback_frame( ...
    randn(1, frame.frameLength), frame, previous, 0, "Log-MAP");
verifyEqual(testCase, soft(frame.dataIndices), ...
    previous(frame.dataIndices), "AbsTol", 1e-12);
end
