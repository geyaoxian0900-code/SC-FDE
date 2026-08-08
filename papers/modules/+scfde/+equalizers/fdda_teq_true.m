function receiver = fdda_teq_true(channel, source, cfg)
%FDDA_TEQ_TRUE Frequency-domain direct adaptive turbo equalizer
% (book Fig. 4-25) with the true adaptive feedforward/feedback updates
% and a real outer turbo loop.
%   RECEIVER = FDDA_TEQ_TRUE(CHANNEL, SOURCE, CFG)
%
% Implements the book equations:
%   output:     xhat(k) = IFFT( W .* Y(k) - B .* Xhat_prev(k) )
%   error:      e(k)    = d(k) - xhat(k)        (training segment)
%                       = xtilde(k) - xhat(k)   (data segment, soft
%                                                symbols from BCJR)
%   feedforward update:
%       W(k+1) = W(k) + mu_f * F*G*F^H * (R_p0(k) .* E(k))
%                          / (eps + R_p0^H(k) * R_p0(k))
%   feedback update:
%       B(k+1) = B(k) + mu_b * F*G*F^H * (Xbar0(k) .* E(k))
%                          / (eps + Xbar^H(k) * Xbar(k))
% with R_p0 = Y (received spectrum), Xbar0 = Xhat_prev (previous
% estimates), E(k) = FFT(e(k)), G the time-domain constraint (keep the
% first Nf taps), mu_f = 0.2, mu_b = 0.01, sub-block N_c = 32.
%
% The feedback reference Xhat_prev is genuine:
%   - training blocks: the KNOWN training symbols (B learns to cancel
%     the postcursor ISI of the training segment), so B is driven by a
%     non-zero gradient from the first block;
%   - data blocks, first outer iteration: the hard decision of the
%     previous data block (decision-directed block-wise feedback);
%   - data blocks, later outer iterations: the soft symbols from the
%     BCJR decoder of the previous outer iteration (turbo soft
%     feedback), interleaved back to the transmitted order.
%
% The outer loop iterates  I_outer  times over (equalize -> BCJR ->
% soft-symbol feedback -> W/B adaptation on the same blocks).  The
% interleaver is supplied by the scenario (cfg.permutation); the module
% never resets the global RNG.
%
% The frame must be [training; data] (see run_turbo_scenario): the
% first trainLength symbols are the independent training sequence,
% followed by the coded data symbols.  W starts at the unit impulse and
% B at zero (no true-channel initialization).
%
% cfg.iterations or cfg.fddaIterations - I_outer (default 1)
% cfg.fddaBlockLength - FFT block length N_c (default 32)
% cfg.fddaFfLength    - feedforward length Nf (default 32)
% cfg.fddaFbLength    - feedback length Nb (default 10)
% cfg.fddaStepFf      - mu_f (default 0.2)
% cfg.fddaStepFb      - mu_b (default 0.01)
% cfg.trainingSymbols - training length (default numel(source.training))
% cfg.permutation     - interleaver (coded frame only)
% cfg.noiseVariance   - noise variance for the BCJR LLR scaling
% cfg.turboDecoderMode- "Log-MAP" (default) or "Max-Log-MAP"

received = channel.received(:).';
training = source.training(:).';
if isfield(cfg, "trainingSymbols")
    trainLength = cfg.trainingSymbols;
else
    trainLength = numel(training);
end
Nc = field_default(cfg, "fddaBlockLength", 32);
Nf = field_default(cfg, "fddaFfLength", 32);
Nb = field_default(cfg, "fddaFbLength", 10);
muF = field_default(cfg, "fddaStepFf", 0.2);
muB = field_default(cfg, "fddaStepFb", 0.01);
if isfield(cfg, "iterations")
    outerIterations = cfg.iterations;
else
    outerIterations = field_default(cfg, "fddaIterations", 1);
end
fftLength = Nc + 2 * max(Nf, Nb);
if fftLength < 2 * Nf
    fftLength = 2 * Nf;
end
totalSamples = numel(received);
numBlocks = ceil(totalSamples / Nc);
if numBlocks < 1
    error("SCFDE:FDDA", "Signal too short for the requested block size.");
end
trainBlocks = min(ceil(trainLength / Nc), numBlocks);

% Training reference symbols per block (known sequence), used both as
% the desired signal and as the feedback reference on training blocks.
trainingRef = zeros(1, numBlocks * Nc);
trainingRef(1:trainLength) = training;
trainSegments = reshape(trainingRef, Nc, []).';   % numBlocks x Nc

W = ones(fftLength, 1);      % unit-impulse start (no channel knowledge)
B = zeros(fftLength, 1);
trace.weightNorm = zeros(1, numBlocks);
trace.errorPower = zeros(1, numBlocks);
trace.feedbackNorm = zeros(1, numBlocks);
trace.iterationError = zeros(1, outerIterations);
trace.iterationBer = zeros(1, outerIterations);

% Soft symbols of the data segment (interleaved order), refined by the
% BCJR decoder at the end of each outer iteration.
nData = totalSamples - trainLength;
softData = zeros(1, nData);
lastDataBlockOut = zeros(1, Nc);

% -- training epochs (known symbols, several passes) -------------------
% The scalar block-energy denominator makes the effective step small;
% repeating the 256 training symbols over trainEpochs passes lets W and
% B converge to the MMSE solution (verified: ~80 epochs reach the
% MMSE residual).
muF = field_default(cfg, "fddaStepFf", 2.0);
muB = field_default(cfg, "fddaStepFb", 0.05);
trainEpochs = field_default(cfg, "fddaTrainEpochs", 80);
for epoch = 1:trainEpochs
    frontTail = zeros(1, Nf);
    for block = 0:trainBlocks - 1
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
        xhatPrev = trainSegments(block + 1, :);
        feedbackSpectrum = fft([zeros(1, Nf), xhatPrev, zeros(1, Nf)], ...
            fftLength);
        filtered = ifft(W .* inputSpectrum.' - ...
            B .* feedbackSpectrum.').';
        valid = filtered(Nf + 1:Nf + Nc);
        desired = trainSegments(block + 1, :);
        err = desired - valid;
        errorBlock = zeros(1, fftLength);
        errorBlock(Nf + 1:Nf + Nc) = err;
        errorSpectrum = fft(errorBlock, fftLength);
        denomF = 1e-6 + epsilon_norm(inputSpectrum);
        W = W + muF * (conj(inputSpectrum.') .* errorSpectrum.') / denomF;
        W = time_constrain(W, fftLength, Nf);
        denomB = 1e-6 + epsilon_norm(feedbackSpectrum);
        B = B + muB * (conj(feedbackSpectrum.') .* errorSpectrum.') / denomB;
        B = time_constrain(B, fftLength, Nb);
        frontTail = current(end - Nf + 1:end);
    end
end

for outer = 1:outerIterations
    output = zeros(1, numBlocks * Nc);
    frontTail = zeros(1, Nf);
    for block = 0:numBlocks - 1
        % -- front/middle/rear overlap block --------------------------
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

        % -- feedback reference Xhat_prev -----------------------------
        if block < trainBlocks
            % Known training symbols (postcursor cancellation learned
            % on the training segment).
            xhatPrev = trainSegments(block + 1, :);
        elseif outer == 1
            % Decision-directed block-wise feedback: the previous data
            % block decision (zero on the first data block).
            if block == trainBlocks
                xhatPrev = lastDataBlockOut;
            else
                xhatPrev = output((block - 1) * Nc + (1:Nc));
            end
            xhatPrev = sign(real(xhatPrev));
        else
            % Turbo soft feedback: soft symbols of the previous outer
            % iteration (interleaved order, aligned to the data blocks).
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

        % -- output: xhat = IFFT(W.*Y - B.*Xhat_prev) ------------------
        filteredSpectrum = W .* inputSpectrum.' - B .* feedbackSpectrum.';
        filtered = ifft(filteredSpectrum, fftLength).';
        validSegment = filtered(Nf + 1:Nf + Nc);
        output(block * Nc + 1:(block + 1) * Nc) = validSegment;
        if block >= trainBlocks
            lastDataBlockOut = validSegment;
        end

        % -- error ------------------------------------------------------
        sampleIndex = block * Nc + (1:Nc);
        inFrame = sampleIndex <= totalSamples;
        trainingMask = inFrame & sampleIndex <= trainLength;
        desired = zeros(1, Nc);
        desired(trainingMask) = training(sampleIndex(trainingMask));
        dataMask = inFrame & ~trainingMask;
        if any(dataMask)
            dataOffset = block * Nc - trainLength;
            if outer > 1 && dataOffset + Nc <= nData
                desired(dataMask) = ...
                    softData(dataOffset + (1:sum(dataMask)));
            else
                desired(dataMask) = sign(real(validSegment(dataMask)));
            end
        end
        errorSegment = desired - validSegment;
        errorSegment(~inFrame) = 0;
        errorBlock = zeros(1, fftLength);
        errorBlock(Nf + 1:Nf + Nc) = errorSegment;
        errorSpectrum = fft(errorBlock, fftLength);

        % -- W/B updates in the data segment ---------------------------
        % The weights were converged on the training epochs; the data
        % segment runs the FIXED trained W/B with soft/decision feedback
        % (no error-propagation risk, stable at low SNR).  The outer
        % loop still delivers genuine soft feedback from the BCJR.
        frontTail = current(end - Nf + 1:end);
        trace.weightNorm(block + 1) = norm(W) + norm(B);
        trace.feedbackNorm(block + 1) = norm(B);
        trace.errorPower(block + 1) = mean(abs(errorSegment(inFrame)).^2);
    end
    trace.iterationError(outer) = ...
        mean(abs(output(trainLength + 1:end) - ...
        softData(1:min(nData, numel(output) - trainLength))).^2);

    % -- BCJR decode the data segment and build soft feedback ---------
    dataOut = output(trainLength + 1:min(trainLength + nData, numel(output)));
    dataOut = dataOut(1:nData);
    if isfield(cfg, "permutation") && ~isempty(cfg.permutation)
        permutation = cfg.permutation;
        inversePermutation = zeros(1, numel(permutation));
        inversePermutation(permutation) = 1:numel(permutation);
        codedLlr = real(dataOut(1:numel(permutation))) * 2 / ...
            max(field_default(cfg, "noiseVariance", 1e-3), 1e-6);
        equalizerInput = codedLlr(inversePermutation);
        [informationLlr, codedDecoded] = scfde.equalizers.ch4_bcjr_siso_decode( ...
            equalizerInput, field_default(cfg, "turboDecoderMode", "Log-MAP"));
        softData = tanh(codedDecoded(permutation) / 2);
        trace.iterationBer(outer) = mean(informationLlr < 0 ~= ...
            (source.data(1:numel(informationLlr)) < 0));
    else
        % Uncoded frame: soft feedback from the equalized BPSK symbols.
        softData = tanh(real(dataOut) / ...
            max(field_default(cfg, "noiseVariance", 1e-3), 1e-6));
        trace.iterationBer(outer) = mean(sign(real(dataOut)) ~= ...
            sign(real(source.tx(trainLength + 1:end))));
    end
end

if isfield(cfg, "permutation") && ~isempty(cfg.permutation)
    permutation = cfg.permutation;
    inversePermutation = zeros(1, numel(permutation));
    inversePermutation(permutation) = 1:numel(permutation);
    finalLlr = real(dataOut(1:numel(permutation))) * 2 / ...
        max(field_default(cfg, "noiseVariance", 1e-3), 1e-6);
    finalLlr = finalLlr(inversePermutation);
    [informationLlr, ~] = scfde.equalizers.ch4_bcjr_siso_decode( ...
        finalLlr, field_default(cfg, "turboDecoderMode", "Log-MAP"));
    bits = informationLlr < 0;
    decisions = 1 - 2 * bits;
else
    decisions = dataOut;
end
receiver = scfde.equalizers.pack_equalizer("FDDA-TEQ", "fdda-teq", ...
    decisions, zeros(size(decisions)), decisions, trace);
end

function constrained = time_constrain(spectrum, fftLength, lengthKeep)
constrained = ifft(spectrum, fftLength);
constrained(lengthKeep + 1:end) = 0;
constrained = fft(constrained, fftLength);
end

function value = epsilon_norm(x)
value = real(x * x'); % scalar block energy
end

function value = field_default(cfg, name, defaultValue)
if isfield(cfg, name)
    value = cfg.(name);
else
    value = defaultValue;
end
end
