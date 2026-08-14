function tests = test_fdda_eq_4_74_82
%TEST_FDDA_EQ_4_74_82  Book (4-74)~(4-82) FDDA equation/structure tests.
%
% Scan-confirmed conventions (human review of book/26.png pages 107-110
% and book/27.png pages 111-114; see report dated 2026-08):
%   (4-74) r_m(k) = [y_pre^{Nf}; y_cur^{N}; y_post^{Nb}], FFT length
%          Nf + N + Nb, sliding-window step N_s < N (overlapping windows,
%          one filter update every N_s symbols)
%   (4-75) feedback window = [xtilde_pre^{Nf}; 0_N; xtilde_post^{Nb}]
%   (4-77) Xhat = sum_m conj(W_m) .* R_m + B .* Xtilde
%   (4-80)/(4-82) W_m/B updates with per-element scalar denominator
%          eps + R_m^H R_m and time-domain constraint F G F^{-1};
%          gamma_f^i / gamma_b^i indexed by the INNER iteration i = 1, 2, ...
%          (first inner round scale = gamma^1), identical for all windows
%          inside one inner round
%   (4-81) W_m^i(1) = W_m^{i-1}(K), B^i(1) = B^{i-1}(K)  (inner rounds)
%   The outer iteration is the equalizer/decoder exchange loop; the LAST
%   inner-round output enters the decoder.
%
% STILL SOURCE-UNCERTAIN: how overlapping window outputs are stitched into
% the final symbol sequence.  Therefore multi-window tests below compare
% PER-WINDOW trace fields (outputSpectrum, feedbackHistory, weightHistory,
% stepScale, finalW/finalB) and never assert the frame-level dataOut of an
% overlapping run; dataOut is asserted only for the single-window M=1
% fixture (no stitching involved).
%
% Target (future) kernel interface:
%   [dataOut, trace] = ch4_fdda_teq_core(receivedBranches, training,
%                                        params, feedbackFn)
%   receivedBranches : M x frameLength (rows = independent elements)
%   params           : blockLength N, ffLength Nf, fbLength Nb,
%                      hopLength Ns, ffConstraintLength, fbConstraintLength,
%                      stepFf, stepFb, innerIterations, outerIterations,
%                      forgettingF, forgettingB, denomMode ("equation"),
%                      trainLength, decisionFn, regularization,
%                      referenceData (optional)
%   feedbackFn(round, dataOut) : FRAME-ALIGNED sequence of length
%                      frameLength used as the feedback/error reference of
%                      the NEXT inner round (round = just-finished round)
%
% Trace field semantics exercised below:
%   weightHistory{innerRound, window} / feedbackWeightHistory{...} hold the
%   filter weights BEFORE that window's update, so {2,1} proves (4-81).
% The direct multi-element tests set outerIterations=1: the outer loop is
% the wrapper-level equalizer/decoder exchange, while the equation-level
% tests target the inner-round loop; this also keeps the legacy kernel's
% flattened-input failure surface to the missing-trace RED.
%
% Every oracle below is independent arithmetic; no production helper is
% used to compute expected values.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
papersDir = fileparts(fileparts(mfilename("fullpath")));
addpath(papersDir);
addpath(fullfile(papersDir, "modules"));
testCase.TestData.papersDir = papersDir;
end

function testTwoElementFeedforwardGolden(testCase)
% (4-77) with zero feedback (trainLength=0, inner=1): every window output
% must be IFFT{ sum_m conj(W_m).*R_m } with one independently updated W_m
% per element, per-element scalar denominators, and the ASYMMETRIC window
% [Nf; N; Nb] built by direct indexing (overlapping windows, hop < N).
Nf = 3; N = 4; Nb = 2; hop = 2;
fftLength = Nf + N + Nb;
r1 = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j, -0.8+0.5j, 0.6+0.1j];
r2 = [0.5+0.6j, 0.3-0.8j, -0.7+0.1j, 0.9+0.2j, -0.3+0.4j, 0.1-0.6j, ...
    0.8+0.3j, -0.5-0.2j, 0.6-0.7j, 0.2+0.9j, 0.7-0.1j];
frameLength = numel(r1);
branches = [r1; r2];
reg = 1e-6;
params = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", hop, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 1, ...
    "outerIterations", 1, "forgettingF", 0.9, "forgettingB", 0.9, ...
    "denomMode", "equation", "trainLength", 0, "regularization", reg);
params.decisionFn = @(x) sign(real(x));
feedbackFn = @(round, dataOut) zeros(1, frameLength);
[~, trace] = scfde.equalizers.ch4_fdda_teq_core( ...
    branches, [], params, feedbackFn);
if ~isfield(trace, "outputSpectrum") || ~isfield(trace, "finalW")
    verifyTrue(testCase, false, ...
        "trace must expose outputSpectrum and finalW");
    return;
end
% --- independent oracle (direct per-window indexing, zero padding) ------
W = ones(fftLength, 2);
numWindows = floor((frameLength - N) / hop) + 1;
expectedSpectra = cell(1, numWindows);
for win = 0:numWindows - 1
    start = 1 + win * hop;
    preRange = start - Nf:start - 1;
    curRange = start:start + N - 1;
    postRange = start + N:start + N + Nb - 1;
    filtered = zeros(fftLength, 1);
    R = zeros(fftLength, 2);
    for m = 1:2
        window = zeros(1, fftLength);
        preIdx = preRange(preRange >= 1) - (start - Nf - 1);
        window(preIdx) = branches(m, preRange(preRange >= 1));
        window(Nf + 1:Nf + N) = branches(m, curRange);
        postIn = postRange <= frameLength;
        window(Nf + N + (1:sum(postIn))) = branches(m, postRange(postIn));
        R(:, m) = fft(window, fftLength).';
        filtered = filtered + conj(W(:, m)) .* R(:, m);   % (4-77), B=0
    end
    if win == numWindows - 1
        WBeforeLast = W; RLast = R;    % state of the last window's OUTPUT
    end
    expectedSpectra{win + 1} = filtered;
    timeOut = ifft(filtered, fftLength);
    validOut = timeOut(Nf + 1:Nf + N).';
    d = sign(real(validOut));
    E = fft([zeros(1, Nf), d - validOut, zeros(1, Nb)], fftLength).';
    for m = 1:2
        denom = reg + real(R(:, m)' * R(:, m));          % eps + R_m^H R_m
        W(:, m) = W(:, m) + 0.9 * 0.2 * (conj(R(:, m)) .* E) / denom;
        wT = ifft(W(:, m), fftLength); wT(Nf + 1:end) = 0;
        W(:, m) = fft(wT, fftLength);
    end
end
verifyEqual(testCase, trace.finalW, W, "AbsTol", 1e-12, ...
    "per-element W_m must follow the (4-82) oracle");
for win = 1:numWindows
    verifyEqual(testCase, trace.outputSpectrum{1, win}, ...
        expectedSpectra{win}, "AbsTol", 1e-12);
end
% Negative forms must differ from the confirmed output equation, using
% the SAME weight state that produced the last window's output.
plusSpectrum = expectedSpectra{end};
noConj = WBeforeLast(:, 1) .* RLast(:, 1) + ...
    WBeforeLast(:, 2) .* RLast(:, 2);                     % missing conj(W)
verifyNotEqual(testCase, plusSpectrum, noConj, ...
    "missing conj(W) must differ from the book output");
verifyNotEqual(testCase, W(:, 1), W(:, 2), ...
    "per-element weights must evolve independently");
end

function testPlusFeedbackSignGolden(testCase)
% (4-77) with NONZERO feedback on inner round 2 (deterministic frame-
% aligned sequence): the feedback term must be ADDED: + B .* Xtilde.
% Negative minus form must differ.
Nf = 3; N = 4; Nb = 2; hop = 2;
fftLength = Nf + N + Nb;
r1 = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j, -0.8+0.5j, 0.6+0.1j];
r2 = [0.5+0.6j, 0.3-0.8j, -0.7+0.1j, 0.9+0.2j, -0.3+0.4j, 0.1-0.6j, ...
    0.8+0.3j, -0.5-0.2j, 0.6-0.7j, 0.2+0.9j, 0.7-0.1j];
frameLength = numel(r1);
branches = [r1; r2];
reg = 1e-6;
pattern = [1, -1, 1, 1, -1, -1, 1, -1, 1, -1, -1, 1, -1, 1, 1, -1];
fbSeq = repmat(pattern, 1, ceil(frameLength / 16)); fbSeq = fbSeq(1:frameLength);
params = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", hop, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 2, ...
    "outerIterations", 1, "forgettingF", 0.9, "forgettingB", 0.9, ...
    "denomMode", "equation", "trainLength", 0, "regularization", reg);
params.decisionFn = @(x) sign(real(x));
feedbackFn = @(round, dataOut) fbSeq;     % frame-aligned deterministic seq
[~, trace] = scfde.equalizers.ch4_fdda_teq_core( ...
    branches, [], params, feedbackFn);
if ~isfield(trace, "outputSpectrum") || ~isfield(trace, "finalB")
    verifyTrue(testCase, false, ...
        "trace must expose outputSpectrum and finalB");
    return;
end
% --- independent oracle (two inner rounds, PLUS feedback) --------------
W = ones(fftLength, 2);
B = zeros(fftLength, 1);
numWindows = floor((frameLength - N) / hop) + 1;
expectedSecond = cell(1, numWindows);
secondB = cell(1, numWindows);
for round = 1:2
    for win = 0:numWindows - 1
        start = 1 + win * hop;
        preRange = start - Nf:start - 1;
        curRange = start:start + N - 1;
        postRange = start + N:start + N + Nb - 1;
        filtered = zeros(fftLength, 1);
        R = zeros(fftLength, 2);
        for m = 1:2
            window = zeros(1, fftLength);
            preIdx = preRange(preRange >= 1) - (start - Nf - 1);
            window(preIdx) = branches(m, preRange(preRange >= 1));
            window(Nf + 1:Nf + N) = branches(m, curRange);
            postIn = postRange <= frameLength;
            window(Nf + N + (1:sum(postIn))) = branches(m, postRange(postIn));
            R(:, m) = fft(window, fftLength).';
            filtered = filtered + conj(W(:, m)) .* R(:, m);
        end
        % (4-75) feedback window [xtilde_pre^{Nf}; 0_N; xtilde_post^{Nb}]
        fb = zeros(1, fftLength);
        if round >= 2
            preIdx = preRange(preRange >= 1) - (start - Nf - 1);
            fb(preIdx) = fbSeq(preRange(preRange >= 1));
            postIn = postRange <= frameLength;
            fb(Nf + N + (1:sum(postIn))) = fbSeq(postRange(postIn));
        end
        Xtilde = fft(fb, fftLength).';
        filtered = filtered + B .* Xtilde;                 % PLUS feedback
        if round == 2
            expectedSecond{win + 1} = filtered;
            secondB{win + 1} = B;
        end
        timeOut = ifft(filtered, fftLength);
        validOut = timeOut(Nf + 1:Nf + N).';
        if round == 1
            d = sign(real(validOut));
        else
            d = fbSeq(curRange);
        end
        E = fft([zeros(1, Nf), d - validOut, zeros(1, Nb)], fftLength).';
        for m = 1:2
            denom = reg + real(R(:, m)' * R(:, m));
            W(:, m) = W(:, m) + 0.9^round * 0.2 * ...
                (conj(R(:, m)) .* E) / denom;
            wT = ifft(W(:, m), fftLength); wT(Nf + 1:end) = 0;
            W(:, m) = fft(wT, fftLength);
        end
        denomB = reg + real(Xtilde' * Xtilde);
        B = B + 0.9^round * 0.01 * (conj(Xtilde) .* E) / denomB;
        bT = ifft(B, fftLength); bT(Nb + 1:end) = 0;
        B = fft(bT, fftLength);
    end
end
for win = 1:numWindows
    verifyEqual(testCase, trace.outputSpectrum{2, win}, ...
        expectedSecond{win}, "AbsTol", 1e-12);
end
verifyEqual(testCase, trace.finalB, B, "AbsTol", 1e-12);
% Negative: the minus form must differ wherever B .* Xtilde is nonzero.
win = numWindows;                             % last window of round 2
start = 1 + (win - 1) * hop;
preRange = start - Nf:start - 1;
postRange = start + N:start + N + Nb - 1;
fbMinus = zeros(1, fftLength);
preIdx = preRange(preRange >= 1) - (start - Nf - 1);
fbMinus(preIdx) = fbSeq(preRange(preRange >= 1));
postIn = postRange <= frameLength;
fbMinus(Nf + N + (1:sum(postIn))) = fbSeq(postRange(postIn));
XtildeMinus = fft(fbMinus, fftLength).';
minusVariant = expectedSecond{win} - 2 * secondB{win} .* XtildeMinus;
verifyNotEqual(testCase, expectedSecond{win}, minusVariant, ...
    "minus feedback must differ from the book plus feedback");
end

function testPerElementDenominatorsAndIndependence(testCase)
% (4-80)/(4-82): the error E is computed ONCE per window from the
% COMBINED output sum_m conj(W_m).*R_m (so changing any element changes
% the common error and every element's update), and each element's weight
% is then updated with its OWN R_m and its OWN scalar denominator
% eps + R_m^H R_m.  A single shared denominator must differ.
Nf = 3; N = 4; Nb = 2; hop = 2;
fftLength = Nf + N + Nb;
r1 = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j, -0.8+0.5j, 0.6+0.1j];
r2 = [0.5+0.6j, 0.3-0.8j, -0.7+0.1j, 0.9+0.2j, -0.3+0.4j, 0.1-0.6j, ...
    0.8+0.3j, -0.5-0.2j, 0.6-0.7j, 0.2+0.9j, 0.7-0.1j];
frameLength = numel(r1);
reg = 1e-6;
params = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", hop, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 1, ...
    "outerIterations", 1, "forgettingF", 0.9, "forgettingB", 0.9, ...
    "denomMode", "equation", "trainLength", 0, "regularization", reg);
params.decisionFn = @(x) sign(real(x));
feedbackFn = @(round, dataOut) zeros(1, frameLength);
[~, trace] = scfde.equalizers.ch4_fdda_teq_core([r1; r2], [], params, feedbackFn);
if ~isfield(trace, "finalW")
    verifyTrue(testCase, false, "trace must expose finalW");
    return;
end
if size(trace.finalW, 2) < 2
    verifyTrue(testCase, false, ...
        "finalW must have one column per element");
    return;
end
% --- independent oracle: common error, per-element denominators --------
numWindows = floor((frameLength - N) / hop) + 1;
WPerElement = ones(fftLength, 2);
WShared = ones(fftLength, 2);
for pass = 1:2
    W = ones(fftLength, 2);
    for win = 0:numWindows - 1
        start = 1 + win * hop;
        preRange = start - Nf:start - 1;
        curRange = start:start + N - 1;
        postRange = start + N:start + N + Nb - 1;
        window1 = zeros(1, fftLength);
        preIdx = preRange(preRange >= 1) - (start - Nf - 1);
        window1(preIdx) = r1(preRange(preRange >= 1));
        window1(Nf + 1:Nf + N) = r1(curRange);
        postIn = postRange <= frameLength;
        window1(Nf + N + (1:sum(postIn))) = r1(postRange(postIn));
        window2 = zeros(1, fftLength);
        window2(preIdx) = r2(preRange(preRange >= 1));
        window2(Nf + 1:Nf + N) = r2(curRange);
        window2(Nf + N + (1:sum(postIn))) = r2(postRange(postIn));
        R1 = fft(window1, fftLength).';
        R2 = fft(window2, fftLength).';
        filtered = conj(W(:, 1)) .* R1 + conj(W(:, 2)) .* R2;  % (4-77)
        timeOut = ifft(filtered, fftLength);
        validOut = timeOut(Nf + 1:Nf + N).';
        d = sign(real(validOut));
        E = fft([zeros(1, Nf), d - validOut, zeros(1, Nb)], fftLength).';
        if pass == 1
            W(:, 1) = W(:, 1) + 0.9 * 0.2 * (conj(R1) .* E) / ...
                (reg + real(R1' * R1));
            W(:, 2) = W(:, 2) + 0.9 * 0.2 * (conj(R2) .* E) / ...
                (reg + real(R2' * R2));
        else
            denomShared = reg + real(R1' * R1) + real(R2' * R2);
            W(:, 1) = W(:, 1) + 0.9 * 0.2 * (conj(R1) .* E) / denomShared;
            W(:, 2) = W(:, 2) + 0.9 * 0.2 * (conj(R2) .* E) / denomShared;
        end
        wT1 = ifft(W(:, 1), fftLength); wT1(Nf + 1:end) = 0;
        W(:, 1) = fft(wT1, fftLength);
        wT2 = ifft(W(:, 2), fftLength); wT2(Nf + 1:end) = 0;
        W(:, 2) = fft(wT2, fftLength);
    end
    if pass == 1
        WPerElement = W;
    else
        WShared = W;
    end
end
verifyEqual(testCase, trace.finalW, WPerElement, "AbsTol", 1e-12, ...
    "per-element updates must use the common error and per-element denominators");
verifyNotEqual(testCase, WPerElement, WShared, ...
    "a shared denominator must differ from the per-element denominators");
end

function testFeedbackMiddleStrictlyZeroAndFirstInnerZero(testCase)
% (4-75): the current window's own N positions are STRICTLY zero; the
% first inner round has zero feedback on the data segment.
Nf = 3; N = 4; Nb = 2; hop = 2;
frameLength = 11;
r = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j, -0.8+0.5j, 0.6+0.1j];
pattern = [1, -1, 1, 1, -1, -1, 1, -1, 1, -1, -1, 1, -1, 1, 1, -1];
fbSeq = repmat(pattern, 1, ceil(frameLength / 16)); fbSeq = fbSeq(1:frameLength);
params = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", hop, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 2, ...
    "outerIterations", 3, "forgettingF", 0.9, "forgettingB", 0.9, ...
    "denomMode", "equation", "trainLength", 0, "regularization", 1e-6);
params.decisionFn = @(x) sign(real(x));
[~, trace] = scfde.equalizers.ch4_fdda_teq_core(r, [], params, ...
    @(round, dataOut) fbSeq);
if ~isfield(trace, "feedbackHistory")
    verifyTrue(testCase, false, "trace must expose feedbackHistory");
    return;
end
numWindows = floor((frameLength - N) / hop) + 1;
for win = 1:numWindows
    verifyEqual(testCase, trace.feedbackHistory{1, win}, ...
        zeros(1, Nf + N + Nb), "AbsTol", 0, ...
        "first inner round data feedback must be all zero");
end
for win = 1:numWindows
    fb = trace.feedbackHistory{2, win};
    start = 1 + (win - 1) * hop;
    preRange = start - Nf:start - 1;
    postRange = start + N:start + N + Nb - 1;
    verifyEqual(testCase, fb(Nf + 1:Nf + N), zeros(1, N), "AbsTol", 0, ...
        "current window positions must be strictly zero");
    expectedPre = zeros(1, Nf);
    preIdx = preRange(preRange >= 1) - (start - Nf - 1);
    expectedPre(preIdx) = fbSeq(preRange(preRange >= 1));
    verifyEqual(testCase, fb(1:Nf), expectedPre, "AbsTol", 1e-12);
    expectedPost = zeros(1, Nb);
    postIn = postRange <= frameLength;
    expectedPost(1:sum(postIn)) = fbSeq(postRange(postIn));
    verifyEqual(testCase, fb(Nf + N + 1:end), expectedPost, "AbsTol", 1e-12);
end
end

function testInnerIterationInheritanceEq481(testCase)
% (4-81): inner round 2 must start from the EXACT final W/B of inner
% round 1: W_m^2(1) = W_m^1(K), B^2(1) = B^1(K).
Nf = 3; N = 4; Nb = 2; hop = 2;
fftLength = Nf + N + Nb;
frameLength = 11;
r1 = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j, -0.8+0.5j, 0.6+0.1j];
r2 = [0.5+0.6j, 0.3-0.8j, -0.7+0.1j, 0.9+0.2j, -0.3+0.4j, 0.1-0.6j, ...
    0.8+0.3j, -0.5-0.2j, 0.6-0.7j, 0.2+0.9j, 0.7-0.1j];
branches = [r1; r2];
pattern = [1, -1, 1, 1, -1, -1, 1, -1, 1, -1, -1, 1, -1, 1, 1, -1];
fbSeq = repmat(pattern, 1, ceil(frameLength / 16)); fbSeq = fbSeq(1:frameLength);
reg = 1e-6;
params = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", hop, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 2, ...
    "outerIterations", 1, "forgettingF", 0.9, "forgettingB", 0.9, ...
    "denomMode", "equation", "trainLength", 0, "regularization", reg);
params.decisionFn = @(x) sign(real(x));
[~, trace] = scfde.equalizers.ch4_fdda_teq_core(branches, [], params, ...
    @(round, dataOut) fbSeq);
if ~isfield(trace, "weightHistory") || ...
        ~isfield(trace, "feedbackWeightHistory")
    verifyTrue(testCase, false, ...
        "trace must expose weightHistory and feedbackWeightHistory");
    return;
end
% --- independent oracle ------------------------------------------------
W = ones(fftLength, 2);
B = zeros(fftLength, 1);
numWindows = floor((frameLength - N) / hop) + 1;
for round = 1:2
    for win = 0:numWindows - 1
        start = 1 + win * hop;
        preRange = start - Nf:start - 1;
        curRange = start:start + N - 1;
        postRange = start + N:start + N + Nb - 1;
        filtered = zeros(fftLength, 1);
        R = zeros(fftLength, 2);
        for m = 1:2
            window = zeros(1, fftLength);
            preIdx = preRange(preRange >= 1) - (start - Nf - 1);
            window(preIdx) = branches(m, preRange(preRange >= 1));
            window(Nf + 1:Nf + N) = branches(m, curRange);
            postIn = postRange <= frameLength;
            window(Nf + N + (1:sum(postIn))) = branches(m, postRange(postIn));
            R(:, m) = fft(window, fftLength).';
            filtered = filtered + conj(W(:, m)) .* R(:, m);
        end
        fb = zeros(1, fftLength);
        if round >= 2
            preIdx = preRange(preRange >= 1) - (start - Nf - 1);
            fb(preIdx) = fbSeq(preRange(preRange >= 1));
            postIn = postRange <= frameLength;
            fb(Nf + N + (1:sum(postIn))) = fbSeq(postRange(postIn));
        end
        Xtilde = fft(fb, fftLength).';
        filtered = filtered + B .* Xtilde;
        timeOut = ifft(filtered, fftLength);
        validOut = timeOut(Nf + 1:Nf + N).';
        if round == 1
            d = sign(real(validOut));
        else
            d = fbSeq(curRange);
        end
        E = fft([zeros(1, Nf), d - validOut, zeros(1, Nb)], fftLength).';
        for m = 1:2
            W(:, m) = W(:, m) + 0.9^round * 0.2 * ...
                (conj(R(:, m)) .* E) / (reg + real(R(:, m)' * R(:, m)));
            wT = ifft(W(:, m), fftLength); wT(Nf + 1:end) = 0;
            W(:, m) = fft(wT, fftLength);
        end
        B = B + 0.9^round * 0.01 * (conj(Xtilde) .* E) / ...
            (reg + real(Xtilde' * Xtilde));
        bT = ifft(B, fftLength); bT(Nb + 1:end) = 0;
        B = fft(bT, fftLength);
    end
    if round == 1
        WAfterInner1 = W; BAfterInner1 = B;   % end state of inner round 1
    end
end
% (4-81): weightHistory holds the PRE-UPDATE weights, so {2,1} must equal
% the exact end state of inner round 1 (not the final two-round state).
verifyEqual(testCase, trace.weightHistory{2, 1}, WAfterInner1, ...
    "AbsTol", 1e-12, ...
    "inner round 2 must inherit the exact final W of inner round 1");
verifyEqual(testCase, trace.feedbackWeightHistory{2, 1}, BAfterInner1, ...
    "AbsTol", 1e-12, ...
    "inner round 2 must inherit the exact final B of inner round 1");
verifyEqual(testCase, trace.finalW, W, "AbsTol", 1e-12, ...
    "finalW must equal the inner-round-2 oracle end state");
verifyEqual(testCase, trace.finalB, B, "AbsTol", 1e-12);
end

function testGammaIndexedByInnerIterationEq482(testCase)
% (4-82): gamma_f^i / gamma_b^i are indexed by the INNER round starting at
% i=1: every window of inner round 1 uses gamma^1, every window of round 2
% uses gamma^2.  A per-window (global counter) decay must fail.
Nf = 3; N = 4; Nb = 2; hop = 2;
frameLength = 11;
r = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j, -0.8+0.5j, 0.6+0.1j];
pattern = [1, -1, 1, 1, -1, -1, 1, -1, 1, -1, -1, 1, -1, 1, 1, -1];
fbSeq = repmat(pattern, 1, ceil(frameLength / 16)); fbSeq = fbSeq(1:frameLength);
gamma = 0.9;
params = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", hop, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 2, ...
    "outerIterations", 3, "forgettingF", gamma, "forgettingB", gamma, ...
    "denomMode", "equation", "trainLength", 0, "regularization", 1e-6);
params.decisionFn = @(x) sign(real(x));
[~, trace] = scfde.equalizers.ch4_fdda_teq_core(r, [], params, ...
    @(round, dataOut) fbSeq);
if ~isfield(trace, "stepScaleF") || ~isfield(trace, "stepScaleB")
    verifyTrue(testCase, false, "trace must expose stepScaleF/stepScaleB");
    return;
end
numWindows = floor((frameLength - N) / hop) + 1;
ssF = trace.stepScaleF;
ssB = trace.stepScaleB;
okSize = isequal(size(ssF), [2, numWindows]);
verifyTrue(testCase, okSize, "stepScaleF must be innerRounds x numWindows");
if ~okSize
    return;
end
verifyEqual(testCase, ssF(1, :), gamma * ones(1, numWindows), ...
    "AbsTol", 1e-12, "inner round 1 must use gamma^1 for every window");
verifyEqual(testCase, ssF(2, :), gamma^2 * ones(1, numWindows), ...
    "AbsTol", 1e-12, "inner round 2 must use gamma^2 for every window");
verifyEqual(testCase, ssB, ssF, "AbsTol", 1e-12, ...
    "gamma_f = gamma_b parameter assumption must hold per round");
end

function testOverlapHopStructure(testCase)
% Scan-confirmed structure: windows slide with N_s < N, one update per
% window, and the trace must expose the window start offsets.
Nf = 3; N = 4; Nb = 2; hop = 2;
frameLength = 11;
r = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j, -0.8+0.5j, 0.6+0.1j];
params = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", hop, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 1, ...
    "outerIterations", 3, "forgettingF", 0.9, "forgettingB", 0.9, ...
    "denomMode", "equation", "trainLength", 0, "regularization", 1e-6);
params.decisionFn = @(x) sign(real(x));
[~, trace] = scfde.equalizers.ch4_fdda_teq_core(r, [], params, ...
    @(round, dataOut) zeros(1, frameLength));
if ~isfield(trace, "windowStarts")
    verifyTrue(testCase, false, "trace must expose windowStarts");
    return;
end
numWindows = floor((frameLength - N) / hop) + 1;
verifyEqual(testCase, numel(trace.windowStarts), numWindows);
verifyEqual(testCase, trace.windowStarts, 1 + (0:numWindows - 1) * hop, ...
    "window starts must slide by hopLength = N_s");
verifyGreaterThan(testCase, N, hop, ...
    "the fixture must use overlapping windows (N_s < N)");
end

function testMEqualsOneDataOutOracle(testCase)
% M=1 with CONTIGUOUS windows (hop = N, no overlap -> dataOut is the
% plain concatenation, no stitching rule involved) must match the
% confirmed equation path: IFFT{ conj(W).*R } per window (zero feedback).
Nf = 3; N = 4; Nb = 2; hop = N;
fftLength = Nf + N + Nb;
r = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j];      % Nf + N + Nb = 9 samples
frameLength = numel(r);
reg = 1e-6;
params = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", hop, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 1, ...
    "outerIterations", 1, "forgettingF", 0.9, "forgettingB", 0.9, ...
    "denomMode", "equation", "trainLength", 0, "regularization", reg);
params.decisionFn = @(x) sign(real(x));
[dataOut, ~] = scfde.equalizers.ch4_fdda_teq_core(r, [], params, ...
    @(round, dataOut) zeros(1, frameLength));
% Independent M=1 oracle (contiguous windows, conj(W), no feedback).
W = ones(fftLength, 1);
numWindows = floor((frameLength - N) / hop) + 1;   % 2 windows, no overlap
expectedData = zeros(1, numWindows * N);
for win = 0:numWindows - 1
    start = 1 + win * hop;
    preRange = start - Nf:start - 1;
    curRange = start:start + N - 1;
    postRange = start + N:start + N + Nb - 1;
    window = zeros(1, fftLength);
    preIdx = preRange(preRange >= 1) - (start - Nf - 1);
    window(preIdx) = r(preRange(preRange >= 1));
    window(Nf + 1:Nf + N) = r(curRange);
    postIn = postRange <= frameLength;
    window(Nf + N + (1:sum(postIn))) = r(postRange(postIn));
    R = fft(window, fftLength).';
    timeOut = ifft(conj(W) .* R, fftLength);
    validOut = timeOut(Nf + 1:Nf + N).';
    expectedData(win * N + 1:(win + 1) * N) = validOut;
    d = sign(real(validOut));
    E = fft([zeros(1, Nf), d - validOut, zeros(1, Nb)], fftLength).';
    W = W + 0.9 * 0.2 * (conj(R) .* E) / (reg + real(R' * R));
    wT = ifft(W, fftLength); wT(Nf + 1:end) = 0; W = fft(wT, fftLength);
end
verifyEqual(testCase, dataOut, expectedData, "AbsTol", 1e-12, ...
    "M=1 contiguous windows must match the confirmed output oracle");
end

function testMEqualsOneFinalWOracle(testCase)
% M=1 finalW must match the per-window update oracle (conj(R).*E with the
% per-window scalar denominator and the F G F^{-1} constraint).
Nf = 3; N = 4; Nb = 2; hop = N;
fftLength = Nf + N + Nb;
r = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j];
frameLength = numel(r);
reg = 1e-6;
params = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", hop, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 1, ...
    "outerIterations", 1, "forgettingF", 0.9, "forgettingB", 0.9, ...
    "denomMode", "equation", "trainLength", 0, "regularization", reg);
params.decisionFn = @(x) sign(real(x));
[~, trace] = scfde.equalizers.ch4_fdda_teq_core(r, [], params, ...
    @(round, dataOut) zeros(1, frameLength));
if ~isfield(trace, "finalW")
    verifyTrue(testCase, false, "trace must expose finalW");
    return;
end
okShape = isequal(size(trace.finalW), [fftLength, 1]);
verifyTrue(testCase, okShape, "M=1 must keep W as a one-column matrix");
if ~okShape
    return;
end
W = ones(fftLength, 1);
numWindows = floor((frameLength - N) / hop) + 1;
for win = 0:numWindows - 1
    start = 1 + win * hop;
    preRange = start - Nf:start - 1;
    curRange = start:start + N - 1;
    postRange = start + N:start + N + Nb - 1;
    window = zeros(1, fftLength);
    preIdx = preRange(preRange >= 1) - (start - Nf - 1);
    window(preIdx) = r(preRange(preRange >= 1));
    window(Nf + 1:Nf + N) = r(curRange);
    postIn = postRange <= frameLength;
    window(Nf + N + (1:sum(postIn))) = r(postRange(postIn));
    R = fft(window, fftLength).';
    timeOut = ifft(conj(W) .* R, fftLength);
    validOut = timeOut(Nf + 1:Nf + N).';
    d = sign(real(validOut));
    E = fft([zeros(1, Nf), d - validOut, zeros(1, Nb)], fftLength).';
    W = W + 0.9 * 0.2 * (conj(R) .* E) / (reg + real(R' * R));
    wT = ifft(W, fftLength); wT(Nf + 1:end) = 0; W = fft(wT, fftLength);
end
verifyEqual(testCase, trace.finalW, W, "AbsTol", 1e-12, ...
    "M=1 finalW must match the confirmed update oracle");
end

function testTraceRecordsEffectiveParameters(testCase)
% The trace must record every effective parameter (including the
% regularization epsilon and the unresolved-parameter marker) so metadata
% can separate formula-structure verification from experiment claims.
Nf = 3; N = 4; Nb = 2;
r = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j];
params = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", N, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 2, ...
    "outerIterations", 3, "forgettingF", 0.9, "forgettingB", 0.9, ...
    "denomMode", "equation", "trainLength", 0, "regularization", 1e-6);
params.decisionFn = @(x) sign(real(x));
[~, trace] = scfde.equalizers.ch4_fdda_teq_core(r, [], params, ...
    @(round, dataOut) zeros(1, numel(r)));
if ~isfield(trace, "effectiveParameters")
    verifyTrue(testCase, false, "trace must record effectiveParameters");
    return;
end
ep = trace.effectiveParameters;
verifyEqual(testCase, ep.elementCount, 1);
verifyEqual(testCase, ep.blockLength, N);
verifyEqual(testCase, ep.ffLength, Nf);
verifyEqual(testCase, ep.fbLength, Nb);
verifyEqual(testCase, ep.hopLength, N);
verifyEqual(testCase, ep.ffConstraintLength, Nf);
verifyEqual(testCase, ep.fbConstraintLength, Nb);
verifyEqual(testCase, ep.stepFf, 0.2);
verifyEqual(testCase, ep.stepFb, 0.01);
verifyEqual(testCase, ep.forgettingF, 0.9);
verifyEqual(testCase, ep.forgettingB, 0.9);
verifyEqual(testCase, ep.denomMode, "equation");
verifyEqual(testCase, ep.innerIterations, 2);
verifyEqual(testCase, ep.outerIterations, 3);
verifyEqual(testCase, ep.regularization, 1e-6);
verifyEqual(testCase, trace.formulaMode, "book-structure");
verifyEqual(testCase, trace.bookExperimentEquivalent, false);
end

function testFddaDfeTeqIgnoresBlmsParameters(testCase)
% fdda-dfe-teq must reuse the shared FDDA kernel: changing BLMS-only
% parameters (blmsStep/blmsLeakage/blmsRegularization) must NOT change
% the output.  The current production calls ch4_iterate_fd_blms_turbo and
% must fail (RED).
infoBits = 512;
trainingSymbols = 256;
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
nv = 10^(2/10);
rng(11, "twister");
permutation = randperm(2 * infoBits);
info = randi([0 1], 1, infoBits);
coded = scfde.equalizers.ch4_convolutional_encode(info);
dataSymbols = 1 - 2 * coded(permutation);
training = 1 - 2 * randi([0 1], 1, trainingSymbols);
tx = [training, dataSymbols];
N = numel(tx);
H = fft([imp, zeros(1, N - numel(imp))]);
received = ifft(H .* fft(tx));
received = received + sqrt(nv/2) * (randn(size(received)) + 1j * randn(size(received)));
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received]);
src = struct("data", 1 - 2 * info, "tx", tx, "training", training);
mkCfg = @(step, leak, reg) struct("noiseVariance", nv, ...
    "trainingSymbols", trainingSymbols, "infoBits", infoBits, ...
    "iterations", 3, "blmsStep", step, "blmsLeakage", leak, ...
    "blmsRegularization", reg, "fddaStepFf", 0.2, "fddaStepFb", 0.01, ...
    "fddaBlockLength", 32, "fddaFfLength", 32, "fddaFbLength", 10, ...
    "fddaHopLength", 8, "fddaInnerIterations", 1, ...
    "permutation", permutation, "turboDecoderMode", "Log-MAP", ...
    "fddaDfeFeedbackMode", "hard");
rA = scfde.equalizers.fdda_dfe_teq(ch, src, mkCfg(0.2, 1e-3, 1e-3));
rB = scfde.equalizers.fdda_dfe_teq(ch, src, mkCfg(0.9, 0.5, 1.0));
verifyEqual(testCase, rA.outputs{1}, rB.outputs{1}, ...
    "changing BLMS-only parameters must not change fdda-dfe-teq");
end

function testFddaDfeTeqRespondsToFddaParameters(testCase)
% fdda-dfe-teq must reuse the shared FDDA kernel: changing an FDDA-only
% parameter must change the CONTINUOUS equalized output/weights.  (Hard
% 512-bit decisions can coincide on a fixed sample even when the filter
% genuinely responds -- the same principle applied to the mu_b
% sensitivity check in test_fblms_and_curve_benchmark.)  The current
% production ignores fddaStepFb and must fail (RED).
infoBits = 512;
trainingSymbols = 256;
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
nv = 10^(2/10);
rng(11, "twister");
permutation = randperm(2 * infoBits);
info = randi([0 1], 1, infoBits);
coded = scfde.equalizers.ch4_convolutional_encode(info);
dataSymbols = 1 - 2 * coded(permutation);
training = 1 - 2 * randi([0 1], 1, trainingSymbols);
tx = [training, dataSymbols];
N = numel(tx);
H = fft([imp, zeros(1, N - numel(imp))]);
received = ifft(H .* fft(tx));
received = received + sqrt(nv/2) * (randn(size(received)) + 1j * randn(size(received)));
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received]);
src = struct("data", 1 - 2 * info, "tx", tx, "training", training);
mkCfg = @(step, leak, reg) struct("noiseVariance", nv, ...
    "trainingSymbols", trainingSymbols, "infoBits", infoBits, ...
    "iterations", 3, "blmsStep", step, "blmsLeakage", leak, ...
    "blmsRegularization", reg, "fddaStepFf", 0.2, "fddaStepFb", 0.01, ...
    "fddaBlockLength", 32, "fddaFfLength", 32, "fddaFbLength", 10, ...
    "fddaHopLength", 8, "fddaInnerIterations", 3, ...
    "permutation", permutation, "turboDecoderMode", "Log-MAP", ...
    "fddaDfeFeedbackMode", "hard");
rA = scfde.equalizers.fdda_dfe_teq(ch, src, mkCfg(0.2, 1e-3, 1e-3));
cfgC = mkCfg(0.2, 1e-3, 1e-3);
cfgC.fddaStepFb = 0.5;
rC = scfde.equalizers.fdda_dfe_teq(ch, src, cfgC);
verifyGreaterThan(testCase, ...
    norm(rA.traces{1}.softEstimates(end, :) - ...
        rC.traces{1}.softEstimates(end, :)), 1e-6, ...
    "changing an FDDA parameter must change the continuous equalized output");
verifyGreaterThan(testCase, ...
    norm(rA.traces{1}.finalB - rC.traces{1}.finalB), 1e-12, ...
    "changing an FDDA parameter must change the feedback filter B");
end

function testFddaDfeTeqTraceIdentifiesFddaKernel(testCase)
% The wrapper trace must identify the shared FDDA kernel and carry the
% honest formula-mode metadata.
infoBits = 512;
trainingSymbols = 256;
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
nv = 10^(2/10);
rng(11, "twister");
permutation = randperm(2 * infoBits);
info = randi([0 1], 1, infoBits);
coded = scfde.equalizers.ch4_convolutional_encode(info);
dataSymbols = 1 - 2 * coded(permutation);
training = 1 - 2 * randi([0 1], 1, trainingSymbols);
tx = [training, dataSymbols];
N = numel(tx);
H = fft([imp, zeros(1, N - numel(imp))]);
received = ifft(H .* fft(tx));
received = received + sqrt(nv/2) * (randn(size(received)) + 1j * randn(size(received)));
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received]);
src = struct("data", 1 - 2 * info, "tx", tx, "training", training);
mkCfg = @(step, leak, reg) struct("noiseVariance", nv, ...
    "trainingSymbols", trainingSymbols, "infoBits", infoBits, ...
    "iterations", 3, "blmsStep", step, "blmsLeakage", leak, ...
    "blmsRegularization", reg, "fddaStepFf", 0.2, "fddaStepFb", 0.01, ...
    "fddaBlockLength", 32, "fddaFfLength", 32, "fddaFbLength", 10, ...
    "fddaHopLength", 8, "fddaInnerIterations", 1, ...
    "permutation", permutation, "turboDecoderMode", "Log-MAP", ...
    "fddaDfeFeedbackMode", "hard");
rA = scfde.equalizers.fdda_dfe_teq(ch, src, mkCfg(0.2, 1e-3, 1e-3));
if ~isfield(rA.traces{1}, "kernel")
    verifyTrue(testCase, false, "trace must identify the FDDA kernel");
    return;
end
verifyEqual(testCase, rA.traces{1}.kernel, "fdda");
verifyEqual(testCase, rA.traces{1}.formulaMode, "book-structure");
verifyEqual(testCase, rA.traces{1}.bookExperimentEquivalent, false);
end

function testWrapperContracts512BitsAndRng(testCase)
% Both registered wrappers must return exactly 512 information decisions
% and must not advance the global RNG.  (Contract regression: this test
% may legitimately PASS before the production rewrite.)
infoBits = 512;
trainingSymbols = 256;
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
nv = 10^(2/10);
rng(11, "twister");
permutation = randperm(2 * infoBits);
info = randi([0 1], 1, infoBits);
coded = scfde.equalizers.ch4_convolutional_encode(info);
dataSymbols = 1 - 2 * coded(permutation);
training = 1 - 2 * randi([0 1], 1, trainingSymbols);
tx = [training, dataSymbols];
N = numel(tx);
H = fft([imp, zeros(1, N - numel(imp))]);
received = ifft(H .* fft(tx));
received = received + sqrt(nv/2) * (randn(size(received)) + 1j * randn(size(received)));
ch = struct("received", received, "impulse", imp, ...
    "branches", [received; received]);
src = struct("data", 1 - 2 * info, "tx", tx, "training", training);
baseCfg = struct("noiseVariance", nv, "trainingSymbols", trainingSymbols, ...
    "infoBits", infoBits, "iterations", 1, ...
    "fddaStepFf", 0.2, "fddaStepFb", 0.01, ...
    "fddaBlockLength", 32, "fddaFfLength", 32, "fddaFbLength", 10, ...
    "fddaHopLength", 8, "fddaInnerIterations", 1, ...
    "fddaForgetting", 0.97, "permutation", permutation, ...
    "turboDecoderMode", "Log-MAP", "fddaDfeFeedbackMode", "hard");
before = rng;
rng(12345, "twister");
seeded = rng;
rTeq = scfde.equalizers.fdda_teq_true(ch, src, baseCfg);
rDfe = scfde.equalizers.fdda_dfe_teq(ch, src, baseCfg);
after = rng;
verifyEqual(testCase, numel(rTeq.outputs{1}), infoBits, ...
    "fdda-teq must return exactly 512 information decisions");
verifyEqual(testCase, numel(rDfe.outputs{1}), infoBits, ...
    "fdda-dfe-teq must return exactly 512 information decisions");
verifyEqual(testCase, after.State, seeded.State, ...
    "wrappers must not advance the global RNG");
verifyEqual(testCase, after.Seed, seeded.Seed);
rng(before);
end

function testInterfaceStructuralRejections(testCase)
% The multi-element kernel must reject structurally invalid inputs loudly.
Nf = 3; N = 4; Nb = 2;
r = [0.9+0.4j, -0.6+0.2j, 0.8-0.3j, 0.3+0.7j, -0.4-0.5j, 0.5+0.2j, ...
    -0.2+0.8j, 0.7-0.3j, 0.4+0.6j];
base = struct("blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", N, "ffConstraintLength", Nf, "fbConstraintLength", Nb, ...
    "stepFf", 0.2, "stepFb", 0.01, "innerIterations", 1, ...
    "outerIterations", 3, "forgettingF", 0.9, "forgettingB", 0.9, ...
    "denomMode", "equation", "trainLength", 0, "regularization", 1e-6);
base.decisionFn = @(x) sign(real(x));
verifyError(testCase, @() scfde.equalizers.ch4_fdda_teq_core( ...
    [r; inf(1, numel(r))], [], base, ...
    @(o, d) zeros(1, numel(r))), "SCFDE:ArrayStructure");
verifyError(testCase, @() scfde.equalizers.ch4_fdda_teq_core( ...
    nan(1, numel(r)), [], base, ...
    @(o, d) zeros(1, numel(r))), "SCFDE:ArrayStructure");
verifyError(testCase, @() scfde.equalizers.ch4_fdda_teq_core( ...
    ones(2, numel(r), 3), [], base, ...
    @(o, d) zeros(1, numel(r))), "SCFDE:ArrayStructure");
% Character input must be rejected as non-numeric.
verifyError(testCase, @() scfde.equalizers.ch4_fdda_teq_core( ...
    'abcdefghi', [], base, ...
    @(o, d) zeros(1, numel(r))), "SCFDE:ArrayStructure");
% Non-positive hop length must be rejected.
cfgHop0 = base; cfgHop0.hopLength = 0;
verifyError(testCase, @() scfde.equalizers.ch4_fdda_teq_core( ...
    r, [], cfgHop0, @(o, d) zeros(1, numel(r))), "SCFDE:ArrayStructure");
% A training sequence shorter than trainLength must be rejected.
cfgShort = base; cfgShort.trainLength = 5;
verifyError(testCase, @() scfde.equalizers.ch4_fdda_teq_core( ...
    r, [1, -1], cfgShort, @(o, d) zeros(1, numel(r))), "SCFDE:ArrayStructure");
% Unknown denominator mode must be rejected.
cfgBadMode = base; cfgBadMode.denomMode = "xyz";
verifyError(testCase, @() scfde.equalizers.ch4_fdda_teq_core( ...
    r, [], cfgBadMode, @(o, d) zeros(1, numel(r))), "SCFDE:ArrayStructure");
% Non-positive regularization must be rejected.
cfgNegReg = base; cfgNegReg.regularization = -1;
verifyError(testCase, @() scfde.equalizers.ch4_fdda_teq_core( ...
    r, [], cfgNegReg, @(o, d) zeros(1, numel(r))), "SCFDE:ArrayStructure");
end
