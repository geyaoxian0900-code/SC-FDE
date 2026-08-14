function [dataOut, trace] = ch4_fdda_teq_core(receivedBranches, training, ...
        params, feedbackFn)
%CH4_FDDA_TEQ_CORE  Frequency-domain direct adaptive (FDDA) equalizer
% kernel: book equations (4-74) through (4-82), per-window and
% multi-element (scan-confirmed structure, book/26.png pp.107-110).
%   [DATAOUT, TRACE] = CH4_FDDA_TEQ_CORE(RECEIVEDBRANCHES, TRAINING,
%                                       PARAMS, FEEDBACKFN)
%
% INPUT
%   receivedBranches  M x frameLength complex matrix of independent
%                     element observations (M=1 rows are legal; the
%                     input is NEVER flattened with received(:).')
%   training          known symbol sequence aligned to frame samples
%                     1..numel(training)
%   params            .blockLength N, .ffLength Nf, .fbLength Nb,
%                     .hopLength Ns (default N; must support Ns < N),
%                     .ffConstraintLength, .fbConstraintLength,
%                     .stepFf mu_f, .stepFb mu_b,
%                     .innerIterations (the formula loop driver),
%                     .outerIterations (wrapper-level metadata only),
%                     .forgettingF gamma_f, .forgettingB gamma_b,
%                     .denomMode ("equation" book denominator; "block"
%                     and "bin" are retained legacy engineering modes),
%                     .trainLength, .decisionFn, .regularization delta,
%                     .referenceData (optional true data symbols)
%   feedbackFn        FEEDBACKFN(innerRound, dataOut) returns the frame
%                     aligned feedback/error sequence for the NEXT inner
%                     round (length frameLength; a legacy nData-length
%                     sequence is accepted and placed at the data region)
%
% FORMULAS (index convention: inner round i = 1..I_inner, window k,
% element m, frequency bin over L = Nf + N + Nb):
%   (4-74) r_m(k) = [y_pre^{Nf}; y_cur^{N}; y_post^{Nb}], zero padding at
%          frame edges, window start s_k = 1 + (k-1) Ns
%   (4-75) x~(k) = [x~_pre^{Nf}; 0_N; x~_post^{Nb}]: the current block's
%          N positions are STRICTLY zero; first inner round has zero data
%          feedback; later rounds use the frame-aligned feedbackFn
%          sequence; training windows use the known training sequence
%   (4-76) R_m(k) = FFT{r_m(k)}, X~(k) = FFT{x~(k)}
%   (4-77) Xhat(k) = sum_m W_m^H .* R_m(k) + B .* X~(k)
%          (conj(W_m), explicit element sum, PLUS feedback)
%   common error: e(k) = d(k) - xhat_valid(k) with ONE shared E(k) =
%          FFT{[0_Nf; e(k); 0_Nb]} for all elements; d = decisionFn(...)
%          in inner round 1 on the data segment, the frame-aligned
%          feedback sequence in later rounds, the known training symbols
%          on training windows
%   (4-82) W_m^(i)(k+1) = W_m^(i)(k) + gamma_f^i mu_f F G_f F^{-1}
%          [R_m* .* E] / (delta + R_m^H R_m)        per-element scalar
%          denominator; B update analogous with gamma_b^i, mu_b and
%          delta + X~^H X~; gamma^i indexed by the INNER round starting
%          at i=1 (identical scale for every window of one round)
%   (4-81) W/B initialized ONCE outside the inner loop and inherited
%          across inner rounds (never reset)
%
% dataOut FREEZE: for hopLength == blockLength (contiguous windows, no
% overlap) the valid N-point segments are concatenated and the data
% region is extracted; for hopLength < blockLength the overlapping-output
% stitching rule is NOT source-confirmed, so dataOut = [] and no
% invented stitching drives any downstream decoder.
%
% LEGACY COMPATIBILITY (wrapper migration is a later task): when
% params.innerIterations is absent, the kernel runs params.outerIterations
% rounds as the inner loop (the legacy wrapper's pass count) and records
% the effective value; legacy trace fields (iterationMse/decisionBer/
% iterationError/feedbackNorm/weightNorm/errorPower/stepScale) are kept.
% This mapping is a compatibility bridge only: the book i index of
% (4-81)/(4-82) is the INNER round, never the outer decoder exchange.
%
% The kernel never calls rng and never reads the true channel for
% initialization: W starts as ones(L, M) (unit impulse) and B at zero.
% trace.formulaMode = "book-structure" and
% trace.bookExperimentEquivalent = false always (gamma values, the
% experiment channel/modulation and the overlap stitching rule remain
% unrecovered/unconfirmed).
%
%   See test_fdda_eq_4_74_82.m for the independent oracles.

% --- input validation (SCFDE:ArrayStructure for structural errors) ----
if ~ismatrix(receivedBranches) || isempty(receivedBranches)
    error("SCFDE:ArrayStructure", ...
        "receivedBranches must be a non-empty 2-D matrix.");
end
if ~isnumeric(receivedBranches)
    error("SCFDE:ArrayStructure", ...
        "receivedBranches must be a numeric matrix.");
end
if ~all(isfinite(receivedBranches(:)))
    error("SCFDE:ArrayStructure", ...
        "receivedBranches must contain only finite values.");
end
if isvector(receivedBranches)
    receivedBranches = receivedBranches(:).';   % 1 x N, never flattened
end
elementCount = size(receivedBranches, 1);
frameLength = size(receivedBranches, 2);
training = training(:).';

% --- parameters --------------------------------------------------------
Nf = field_default(params, "ffLength", 32);
N = field_default(params, "blockLength", 32);
Nb = field_default(params, "fbLength", 10);
hop = field_default(params, "hopLength", N);    % legacy contiguous default
ffConstraint = field_default(params, "ffConstraintLength", Nf);
fbConstraint = field_default(params, "fbConstraintLength", Nb);
muF = field_default(params, "stepFf", 0.2);
muB = field_default(params, "stepFb", 0.01);
outerIterations = field_default(params, "outerIterations", 1);
% Legacy bridge: the old wrapper drove passes through outerIterations;
% the formula loop itself is innerIterations.
innerIterations = field_default(params, "innerIterations", outerIterations);
gammaF = field_default(params, "forgettingF", 0.97);
gammaB = field_default(params, "forgettingB", gammaF);
denomMode = lower(string(field_default(params, "denomMode", "equation")));
delta = field_default(params, "regularization", 1e-6);  % recorded, not book
trainLength = field_default(params, "trainLength", numel(training));
decisionFn = field_default(params, "decisionFn", @(x) sign(real(x)));
if isfield(params, "referenceData")
    referenceData = params.referenceData(:).';
else
    referenceData = [];
end
L = Nf + N + Nb;                                   % FFT length (4-74)
% --- structural parameter validation (uniform SCFDE:ArrayStructure) ----
if ~valid_positive_integer(N) || ~valid_positive_integer(Nf) || ...
        ~valid_positive_integer(Nb) || ~valid_positive_integer(hop) || ...
        ~valid_positive_integer(innerIterations) || ...
        ~valid_positive_integer(outerIterations)
    error("SCFDE:ArrayStructure", ...
        "blockLength/ffLength/fbLength/hopLength/iteration counts " + ...
        "must be positive integers.");
end
if ~valid_nonnegative_integer(ffConstraint) || ...
        ~valid_nonnegative_integer(fbConstraint) || ...
        ffConstraint > L || fbConstraint > L
    error("SCFDE:ArrayStructure", ...
        "constraint lengths must be integers with 0 <= length <= L.");
end
if ~isscalar(delta) || ~isreal(delta) || ~isfinite(delta) || delta <= 0
    error("SCFDE:ArrayStructure", ...
        "regularization must be a positive finite scalar.");
end
if ~valid_nonnegative_integer(trainLength) || ...
        trainLength > numel(training)
    error("SCFDE:ArrayStructure", ...
        "trainLength must satisfy 0 <= trainLength <= numel(training).");
end
if ~ismember(denomMode, ["equation", "block", "bin"])
    error("SCFDE:ArrayStructure", ...
        "denomMode must be 'equation', 'block' or 'bin'.");
end
numWindows = floor((frameLength - N) / hop) + 1;
if numWindows < 1
    error("SCFDE:FDDA", "Signal too short for the requested block size.");
end
nData = frameLength - trainLength;
if nData < 0
    error("SCFDE:ArrayStructure", ...
        "trainLength must not exceed the frame length.");
end

% --- state: one W per element, one common B, initialized once ----------
W = ones(L, elementCount);          % unit-impulse start, no channel info
B = zeros(L, 1);

% --- trace -------------------------------------------------------------
trace.outputSpectrum = cell(innerIterations, numWindows);
trace.feedbackHistory = cell(innerIterations, numWindows);
trace.weightHistory = cell(innerIterations, numWindows);
trace.feedbackWeightHistory = cell(innerIterations, numWindows);
trace.stepScaleF = zeros(innerIterations, numWindows);
trace.stepScaleB = zeros(innerIterations, numWindows);
trace.windowStarts = 1 + (0:numWindows - 1) * hop;
% legacy-compat diagnostics
trace.weightNorm = zeros(innerIterations, numWindows);
trace.feedbackNorm = zeros(innerIterations, numWindows);
trace.errorPower = zeros(innerIterations, numWindows);
trace.iterationMse = zeros(1, innerIterations);
trace.decisionBer = zeros(1, innerIterations);
trace.iterationError = zeros(1, innerIterations);
trace.stepScale = zeros(innerIterations, numWindows);

softData = zeros(1, frameLength);   % frame-aligned feedback for round i+1

for innerRound = 1:innerIterations
    % (4-82) gamma^i: indexed by the INNER round, starting at i = 1; the
    % SAME scale applies to every window of this round.
    scaleF = gammaF^innerRound;
    scaleB = gammaB^innerRound;
    fullOutput = zeros(1, numWindows * N);
    for win = 0:numWindows - 1
        % (4-81) bookkeeping: weights BEFORE this window's update.
        trace.weightHistory{innerRound, win + 1} = W;
        trace.feedbackWeightHistory{innerRound, win + 1} = B;
        s = 1 + win * hop;                          % window start (4-74)

        % -- (4-74)/(4-76): per-element asymmetric windows -------------
        R = zeros(L, elementCount);
        for elementIndex = 1:elementCount
            window = zeros(1, L);
            for preSlot = 1:Nf
                idx = s - Nf - 1 + preSlot;
                if idx >= 1 && idx <= frameLength
                    window(preSlot) = receivedBranches(elementIndex, idx);
                end
            end
            window(Nf + 1:Nf + N) = ...
                receivedBranches(elementIndex, s:s + N - 1);
            for postSlot = 1:Nb
                idx = s + N - 1 + postSlot;
                if idx <= frameLength
                    window(Nf + N + postSlot) = ...
                        receivedBranches(elementIndex, idx);
                end
            end
            R(:, elementIndex) = fft(window, L).';
        end

        % -- (4-75): feedback window, middle N strictly zero ------------
        % Cross-boundary policy (explicit implementation decision, not a
        % book claim): every pre/post position uses the KNOWN training
        % symbol where idx <= trainLength; elsewhere it uses the
        % frame-aligned feedbackFn sequence from inner round >= 2; the
        % first inner round leaves those positions zero.
        fb = zeros(1, L);
        for preSlot = 1:Nf
            idx = s - Nf - 1 + preSlot;
            if idx >= 1 && idx <= trainLength
                fb(preSlot) = training(idx);
            elseif innerRound >= 2 && idx >= 1 && idx <= frameLength
                fb(preSlot) = softData(idx);
            end
        end
        for postSlot = 1:Nb
            idx = s + N - 1 + postSlot;
            if idx <= trainLength
                fb(Nf + N + postSlot) = training(idx);
            elseif innerRound >= 2 && idx <= frameLength
                fb(Nf + N + postSlot) = softData(idx);
            end
        end
        % (middle Nf+1:Nf+N stays zero; first inner round data feedback
        % stays all zero)
        trace.feedbackHistory{innerRound, win + 1} = fb;
        feedbackSpectrum = fft(fb, L).';

        % -- (4-77): output = sum_m conj(W_m).*R_m + B.*X~ -------------
        filtered = zeros(L, 1);
        for elementIndex = 1:elementCount
            filtered = filtered + ...
                conj(W(:, elementIndex)) .* R(:, elementIndex);
        end
        filtered = filtered + B .* feedbackSpectrum;   % PLUS feedback
        trace.outputSpectrum{innerRound, win + 1} = filtered;
        timeOutput = ifft(filtered, L);
        validOutput = timeOutput(Nf + 1:Nf + N).';
        fullOutput(win * N + 1:(win + 1) * N) = validOutput;

        % -- common desired and ONE shared error spectrum --------------
        % Per-sample policy (explicit implementation decision, not a book
        % claim): positions inside the training region use the known
        % training symbol; data positions use decisionFn (inner round 1)
        % or the frame-aligned feedback sequence (inner round >= 2).
        desired = zeros(1, N);
        for pos = 1:N
            idx = s + pos - 1;
            if idx <= trainLength
                desired(pos) = training(idx);
            elseif innerRound == 1
                desired(pos) = decisionFn(validOutput(pos));
            else
                desired(pos) = softData(idx);
            end
        end
        errorSegment = desired - validOutput;
        E = fft([zeros(1, Nf), errorSegment, zeros(1, Nb)], L).';

        % -- (4-82): per-element updates, per-element denominators ------
        for elementIndex = 1:elementCount
            Rm = R(:, elementIndex);
            if strcmpi(denomMode, "bin")            % legacy engineering
                binPower = abs(Rm).^2;
                denom = binPower + 0.05 * mean(binPower) + 1e-6;
                W(:, elementIndex) = W(:, elementIndex) + ...
                    scaleF * muF * (conj(Rm) .* E) ./ denom;
            elseif strcmpi(denomMode, "block")      % legacy engineering
                denom = 1e-6 + real(Rm' * Rm) / L;
                W(:, elementIndex) = W(:, elementIndex) + ...
                    scaleF * muF * (conj(Rm) .* E) / denom;
            else
                denom = delta + real(Rm' * Rm);     % book scalar denom
                W(:, elementIndex) = W(:, elementIndex) + ...
                    scaleF * muF * (conj(Rm) .* E) / denom;
            end
            wTime = ifft(W(:, elementIndex), L);
            wTime(ffConstraint + 1:end) = 0;        % F G_f F^{-1}
            W(:, elementIndex) = fft(wTime, L);
        end
        if strcmpi(denomMode, "bin")
            binPower = abs(feedbackSpectrum).^2;
            denomB = binPower + 0.05 * mean(binPower) + 1e-6;
            B = B + scaleB * muB * (conj(feedbackSpectrum) .* E) ./ denomB;
        elseif strcmpi(denomMode, "block")
            denomB = 1e-6 + real(feedbackSpectrum' * feedbackSpectrum) / L;
            B = B + scaleB * muB * (conj(feedbackSpectrum) .* E) / denomB;
        else
            denomB = delta + real(feedbackSpectrum' * feedbackSpectrum);
            B = B + scaleB * muB * (conj(feedbackSpectrum) .* E) / denomB;
        end
        bTime = ifft(B, L);
        bTime(fbConstraint + 1:end) = 0;            % F G_b F^{-1}
        B = fft(bTime, L);

        % -- trace ------------------------------------------------------
        trace.weightNorm(innerRound, win + 1) = norm(W) + norm(B);
        trace.feedbackNorm(innerRound, win + 1) = norm(B);
        trace.errorPower(innerRound, win + 1) = mean(abs(errorSegment).^2);
        trace.stepScaleF(innerRound, win + 1) = scaleF;
        trace.stepScaleB(innerRound, win + 1) = scaleB;
        trace.stepScale(innerRound, win + 1) = scaleF;   % legacy alias
    end

    % -- dataOut: only the confirmed non-overlapping concatenation ------
    if hop == N
        dataOut = fullOutput(trainLength + 1: ...
            min(trainLength + nData, numel(fullOutput)));
    else
        % Overlap stitching rule is SOURCE-UNCERTAIN: no invented rule.
        dataOut = [];
    end
    if ~isempty(referenceData) && nData > 0 && ~isempty(dataOut)
        trace.iterationMse(innerRound) = ...
            mean(abs(dataOut - referenceData(1:numel(dataOut))).^2);
        trace.decisionBer(innerRound) = ...
            mean(decisionFn(dataOut) ~= referenceData(1:numel(dataOut)));
        trace.softEstimates(innerRound, :) = dataOut;
    end

    % -- feedback sequence for the NEXT inner round ---------------------
    if innerRound < innerIterations
        softData = feedbackFn(innerRound, dataOut);
        if isempty(softData)
            softData = zeros(1, frameLength);
        end
        softData = softData(:).';
        if numel(softData) == frameLength
            % frame-aligned contract: use as is
        elseif numel(softData) == nData && nData > 0
            % legacy wrapper contract: place at the data region
            placed = zeros(1, frameLength);
            placed(trainLength + 1:frameLength) = softData;
            softData = placed;
        else
            error("SCFDE:ArrayStructure", ...
                "feedbackFn must return a frame-aligned sequence of " + ...
                "length frameLength (%d) or the legacy data-region " + ...
                "sequence (%d); got %d.", frameLength, nData, ...
                numel(softData));
        end
    end
end

trace.finalW = W;
trace.finalB = B;
trace.formulaMode = "book-structure";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = struct( ...
    "elementCount", elementCount, ...
    "blockLength", N, "ffLength", Nf, "fbLength", Nb, ...
    "hopLength", hop, ...
    "ffConstraintLength", ffConstraint, ...
    "fbConstraintLength", fbConstraint, ...
    "stepFf", muF, "stepFb", muB, ...
    "forgettingF", gammaF, "forgettingB", gammaB, ...
    "denomMode", denomMode, ...
    "innerIterations", innerIterations, ...
    "outerIterations", outerIterations, ...
    "regularization", delta);
end

function valid = valid_positive_integer(x)
valid = isscalar(x) && isnumeric(x) && isfinite(x) && x > 0 && x == floor(x);
end

function valid = valid_nonnegative_integer(x)
valid = isscalar(x) && isnumeric(x) && isfinite(x) && x >= 0 && x == floor(x);
end

function value = field_default(cfg, name, defaultValue)
if isfield(cfg, name) && ~isempty(cfg.(name))
    value = cfg.(name);
else
    value = defaultValue;
end
end
