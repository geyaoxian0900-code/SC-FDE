function [dataOut, trace] = ch4_fdda_teq_core(received, training, params, softFn)
%CH4_FDDA_TEQ_CORE Shared frequency-domain direct adaptive turbo
% equalizer kernel (book Eqs. 4-81 and 4-82), used by BOTH the
% production fdda-teq module and the Fig. 4-31 benchmark.
%   [DATAOUT, TRACE] = CH4_FDDA_TEQ_CORE(RECEIVED, TRAINING, PARAMS, SOFTFN)
%
% Book equations (chapter 4, pp. 109-111):
%   Eq. (4-81)  at the start of outer iteration i the filter vectors are
%               inherited from the end of iteration i-1:
%                   W^(i)(k) = W^-(K),  B^(i)(k) = B^-(K)
%   Eq. (4-82)  every block k (training mode AND decision-directed mode)
%               updates the filters with the exponential forgetting
%               factors gamma_f^i and gamma_b^i (gamma < 1), where i is
%               the OUTER ITERATION index, so all blocks k inside the
%               same outer iteration use the SAME scale:
%                   W^(i)(k+1) = W^(i)(k) + gamma_f^i * mu_f * F G F^H
%                                   (R^(i)(k) .* E(k)) / (eps + R^H R)
%                   B^(i)(k+1) = B^(i)(k) + gamma_b^i * mu_b * F G F^H
%                                   (Xtilde^(i)(k) .* E(k)) / (eps + Xtilde^H Xtilde)
%   where R = input spectrum, Xtilde = feedback spectrum,
%   E(k) = FFT(e(k)), e = d - xhat on training blocks, decision or
%   soft-symbol error on data blocks, G the time-domain constraint
%   (first Nf / Nb taps).
%   The last inner iteration's output is the filter output fed to the
%   demodulator.
%
% PARAMS fields:
%   blockLength   N_c (default 32)
%   ffLength      N_f (default 32)
%   fbLength      N_b (default 10)
%   stepFf        mu_f (default 0.2)
%   stepFb        mu_b (default 0.01)
%   outerIterations I_outer (default 1)
%   forgettingF   gamma_f (default 0.97); step scale gamma_f^(i-1)
%   forgettingB   gamma_b (default = gamma_f); the book uses separate
%                 factors; taking them equal is a parameter assumption
%   denomMode     'equation' (default, the book Eq. 4-82 scalar
%                 delta + R^H R), 'block' or 'bin' engineering variants
%   trainLength   length of the training segment (default numel(training))
%   decisionFn    decision function on the data segment for the first
%                 outer iteration (default sign(real(.)) for BPSK)
%
% SOFTFN(OUTER, DATAOUT) returns the soft symbols of the data segment
% (transmitted order) to be used as the feedback reference and error
% reference in outer iteration OUTER+1.  It may return [] for the last
% outer iteration.  For outer iteration 1 the kernel uses decisionFn.
%
% TRACE fields:
%   weightNorm    norm(W)+norm(B) per block
%   feedbackNorm  norm(B) per block
%   errorPower    per-block error power
%   iterationMse  per-outer-iteration data MSE against the true data
%                 symbols passed in params.referenceData (if provided)

received = received(:).';
training = training(:).';
trainLength = field_default(params, "trainLength", numel(training));
Nc = field_default(params, "blockLength", 32);
Nf = field_default(params, "ffLength", 32);
Nb = field_default(params, "fbLength", 10);
muF = field_default(params, "stepFf", 0.2);
muB = field_default(params, "stepFb", 0.01);
outerIterations = field_default(params, "outerIterations", 1);
% Book Eq. (4-82) uses separate forgetting factors for the feedforward
% and feedback updates:  gamma_f^i  and  gamma_b^i, where i is the
% OUTER ITERATION index (same scale for all blocks k inside an outer
% iteration).  The defaults take gamma_f = gamma_b (a parameter
% assumption, recorded in the traceability matrix).
gammaF = field_default(params, "forgettingF", 0.97);
gammaB = field_default(params, "forgettingB", gammaF);
denomMode = field_default(params, "denomMode", "equation");
% 'equation' (default) - the book Eq. (4-82) scalar denominator
%                       delta + R^H R (full spectral block energy, no
%                       fftLength division, no empirical term)
% 'block'              - engineering variant: time-domain block energy
%                       (spectral energy / fftLength)
% 'bin'                - engineering variant: per-frequency-bin power
%                       (normalized LMS), fastest but noise-sensitive
decisionFn = field_default(params, "decisionFn", ...
    @(x) sign(real(x)));
if isfield(params, "referenceData")
    referenceData = params.referenceData(:).';
else
    referenceData = [];
end
fftLength = Nc + 2 * max(Nf, Nb);
totalSamples = numel(received);
numBlocks = ceil(totalSamples / Nc);
if numBlocks < 1
    error("SCFDE:FDDA", "Signal too short for the requested block size.");
end
trainBlocks = min(ceil(trainLength / Nc), numBlocks);
nData = totalSamples - trainLength;

trainingRef = zeros(1, numBlocks * Nc);
trainingRef(1:trainLength) = training;
trainSegments = reshape(trainingRef, Nc, []).';   % numBlocks x Nc

W = ones(fftLength, 1);      % unit-impulse start (no channel knowledge)
B = zeros(fftLength, 1);
trace.weightNorm = zeros(outerIterations, numBlocks);
trace.feedbackNorm = zeros(outerIterations, numBlocks);
trace.errorPower = zeros(outerIterations, numBlocks);
trace.stepScale = zeros(outerIterations, numBlocks);
trace.stepScaleF = zeros(outerIterations, numBlocks);
trace.stepScaleB = zeros(outerIterations, numBlocks);
trace.iterationMse = zeros(1, outerIterations);
trace.decisionBer = zeros(1, outerIterations);
softData = zeros(1, nData);
lastDataBlockOut = zeros(1, Nc);

for outer = 1:outerIterations
    % Eq. (4-81): the filters are inherited from the previous outer
    % iteration (W, B persist across the outer loop).
    output = zeros(1, numBlocks * Nc);
    frontTail = zeros(1, Nf);
    for block = 0:numBlocks - 1
        blockStart = block * Nc + 1;
        blockEnd = min(blockStart + Nc - 1, totalSamples);
        current = received(blockStart:blockEnd);
        if numel(current) < Nc
            current = [current, zeros(1, Nc - numel(current))]; %#ok<AGROW>
        end
        rearStart = blockEnd + 1;
        rearEnd = min(rearStart + Nf - 1, totalSamples);
        rear = zeros(1, Nf);
        if rearStart <= totalSamples
            rear(1:rearEnd - rearStart + 1) = received(rearStart:rearEnd);
        end
        inputBlock = [frontTail, current, rear];
        inputSpectrum = fft(inputBlock, fftLength);

        % -- feedback reference Xtilde (Eq. 4-82) ----------------------
        if block < trainBlocks
            xhatPrev = trainSegments(block + 1, :);
        elseif outer == 1
            if block == trainBlocks
                xhatPrev = lastDataBlockOut;
            else
                xhatPrev = output((block - 1) * Nc + (1:Nc));
            end
            xhatPrev = decisionFn(xhatPrev);
        else
            dataOffset = block * Nc - trainLength;
            if dataOffset + Nc <= nData
                xhatPrev = softData(dataOffset + 1:dataOffset + Nc);
            elseif dataOffset < nData
                xhatPrev = [softData(dataOffset + 1:end), ...
                    zeros(1, dataOffset + Nc - nData)];
            else
                xhatPrev = zeros(1, Nc);
            end
        end
        feedbackSpectrum = fft([zeros(1, Nf), xhatPrev, zeros(1, Nf)], ...
            fftLength);

        % -- output: xhat = IFFT(W.*Y - B.*Xtilde) ---------------------
        filteredSpectrum = W .* inputSpectrum.' - B .* feedbackSpectrum.';
        filtered = ifft(filteredSpectrum, fftLength).';
        validSegment = filtered(Nf + 1:Nf + Nc);
        output(block * Nc + 1:(block + 1) * Nc) = validSegment;
        if block >= trainBlocks
            lastDataBlockOut = validSegment;
        end

        % -- error: e = d - xhat ----------------------------------------
        sampleIndex = block * Nc + (1:Nc);
        inFrame = sampleIndex <= totalSamples;
        trainingMask = inFrame & sampleIndex <= trainLength;
        desired = zeros(1, Nc);
        desired(trainingMask) = training(sampleIndex(trainingMask));
        dataMask = inFrame & ~trainingMask;
        if any(dataMask)
            % Error reference on the data segment: the soft symbols of
            % the previous outer iteration (softFn output) for outer>1,
            % the decision otherwise.  The soft symbols enter BOTH the
            % feedback reference Xtilde and the error E(k) of Eq. (4-82).
            dataOffset = block * Nc - trainLength;
            if outer > 1 && dataOffset + Nc <= nData
                desired(dataMask) = ...
                    softData(dataOffset + (1:sum(dataMask)));
            else
                desired(dataMask) = decisionFn(validSegment(dataMask));
            end
        end
        errorSegment = desired - validSegment;
        errorSegment(~inFrame) = 0;
        errorBlock = zeros(1, fftLength);
        errorBlock(Nf + 1:Nf + Nc) = errorSegment;
        errorSpectrum = fft(errorBlock, fftLength);

        % -- Eq. (4-82): W and B updates on EVERY block ----------------
        % The forgetting factors are gamma_f^i and gamma_b^i with i the
        % OUTER ITERATION index (zero-based): ALL blocks k inside the
        % same outer iteration use the SAME scale.
        stepScaleF = gammaF^(outer - 1);
        stepScaleB = gammaB^(outer - 1);
        gradF = conj(inputSpectrum.') .* errorSpectrum.';
        if strcmpi(denomMode, "bin")
            binF = abs(inputSpectrum.').^2;
            denomF = binF + 0.05 * mean(binF) + 1e-6;
            W = W + stepScaleF * muF * gradF ./ denomF;
        elseif strcmpi(denomMode, "block")
            denomF = 1e-6 + epsilon_norm(inputSpectrum) / fftLength;
            W = W + stepScaleF * muF * gradF / denomF;
        else
            % 'equation' (default): the book Eq. (4-82) scalar
            % denominator  delta + R^H R  with the FULL spectral block
            % energy (no fftLength division, no empirical term).
            denomF = 1e-6 + epsilon_norm(inputSpectrum);
            W = W + stepScaleF * muF * gradF / denomF;
        end
        W = time_constrain(W, fftLength, Nf);
        gradB = conj(feedbackSpectrum.') .* errorSpectrum.';
        if strcmpi(denomMode, "bin")
            binB = abs(feedbackSpectrum.').^2;
            denomB = binB + 0.05 * mean(binB) + 1e-6;
            B = B + stepScaleB * muB * gradB ./ denomB;
        elseif strcmpi(denomMode, "block")
            denomB = 1e-6 + epsilon_norm(feedbackSpectrum) / fftLength;
            B = B + stepScaleB * muB * gradB / denomB;
        else
            denomB = 1e-6 + epsilon_norm(feedbackSpectrum);
            B = B + stepScaleB * muB * gradB / denomB;
        end
        B = time_constrain(B, fftLength, Nb);

        frontTail = current(end - Nf + 1:end);
        trace.weightNorm(outer, block + 1) = norm(W) + norm(B);
        trace.feedbackNorm(outer, block + 1) = norm(B);
        trace.errorPower(outer, block + 1) = ...
            mean(abs(errorSegment(inFrame)).^2);
        trace.stepScale(outer, block + 1) = stepScaleF;
        trace.stepScaleF(outer, block + 1) = stepScaleF;
        trace.stepScaleB(outer, block + 1) = stepScaleB;
    end
    dataOut = output(trainLength + 1:min(trainLength + nData, numel(output)));
    dataOut = dataOut(1:nData);
    if ~isempty(referenceData) && nData > 0
        trace.iterationMse(outer) = ...
            mean(abs(dataOut - referenceData).^2);
        trace.decisionBer(outer) = ...
            mean(decisionFn(dataOut) ~= referenceData);
    end
    if outer < outerIterations
        softData = softFn(outer, dataOut);
        if isempty(softData)
            softData = zeros(1, nData);
        end
    end
end
trace.finalW = W;
trace.finalB = B;
end

function constrained = time_constrain(spectrum, fftLength, lengthKeep)
constrained = ifft(spectrum, fftLength);
constrained(lengthKeep + 1:end) = 0;
constrained = fft(constrained, fftLength);
end

function value = epsilon_norm(x)
value = real(x * x');
end

function value = field_default(cfg, name, defaultValue)
if isfield(cfg, name)
    value = cfg.(name);
else
    value = defaultValue;
end
end
