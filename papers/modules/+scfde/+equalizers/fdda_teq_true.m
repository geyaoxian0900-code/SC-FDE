function receiver = fdda_teq_true(channel, source, cfg)
%FDDA_TEQ_TRUE Frequency-domain direct adaptive turbo equalizer
% (book Fig. 4-25) with the true adaptive feedforward/feedback updates.
%   RECEIVER = FDDA_TEQ_TRUE(CHANNEL, SOURCE, CFG)
%
% Implements the book equations:
%   output:     xhat(k) = IFFT( W .* Y - B .* Xhat_prev )
%   error:      e(k)    = d(k) - xhat(k)        (training segment)
%                       = xtilde(k) - xhat(k)   (decision-directed)
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
% The TRAINING segment is taken from source.training (the first
% trainLength symbols of the received frame); the frame must be
% [training; data] (see run_turbo_scenario).  The true channel is NOT
% used for initialization (W starts at the unit impulse, B at zero), so
% the adaptation is genuinely direct.
%
% cfg.fddaBlockLength - FFT block length N_c (default 32)
% cfg.fddaFfLength    - feedforward length Nf (default 32)
% cfg.fddaFbLength    - feedback length Nb (default 10)
% cfg.fddaStepFf      - mu_f (default 0.2)
% cfg.fddaStepFb      - mu_b (default 0.01)
% cfg.fddaIterations  - turbo outer iterations (default 1; the turbo
%                       outer loop with BCJR needs the coded frame)
% cfg.trainingSymbols - training length (default numel(source.training))

received = channel.received(:).';
reference = source.tx(:).';
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
iterations = field_default(cfg, "fddaIterations", 1);
fftLength = Nc + 2 * max(Nf, Nb);
if fftLength < 2 * Nf
    fftLength = 2 * Nf;
end
totalSamples = numel(received);
numBlocks = ceil(totalSamples / Nc);
if numBlocks < 1
    error("SCFDE:FDDA", "Signal too short for the requested block size.");
end

W = ones(fftLength, 1);      % unit-impulse start (no channel knowledge)
B = zeros(fftLength, 1);
output = zeros(1, numBlocks * Nc);
trace.weightNorm = zeros(1, numBlocks);
trace.errorPower = zeros(1, numBlocks);

frontTail = zeros(1, Nf);
for block = 0:numBlocks - 1
    % -- front/middle/rear overlap block ------------------------------
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
    if block == 0
        xhatPrev = zeros(1, Nc);
    else
        xhatPrev = output(block * Nc + (1:Nc));
    end
    feedbackSpectrum = fft([zeros(1, Nf), xhatPrev, zeros(1, Nf)], ...
        fftLength);

    % -- output: xhat = IFFT(W.*Y - B.*Xhat_prev) ----------------------
    filteredSpectrum = W .* inputSpectrum.' - B .* feedbackSpectrum.';
    filtered = ifft(filteredSpectrum, fftLength).';
    validSegment = filtered(Nf + 1:Nf + Nc);
    output(block * Nc + 1:(block + 1) * Nc) = validSegment;

    % -- error ---------------------------------------------------------
    sampleIndex = block * Nc + (1:Nc);
    inFrame = sampleIndex <= totalSamples;
    trainingMask = inFrame & sampleIndex <= trainLength;
    desired = zeros(1, Nc);
    desired(trainingMask) = training(sampleIndex(trainingMask));
    if ~all(trainingMask) && iterations > 1
        % decision-directed on the data segment for the turbo loop
        desired(~trainingMask) = sign(real(validSegment(~trainingMask)));
    elseif ~all(trainingMask)
        desired(~trainingMask) = validSegment(~trainingMask);
    end
    errorSegment = desired - validSegment;
    errorSegment(~inFrame) = 0;
    errorBlock = zeros(1, fftLength);
    errorBlock(Nf + 1:Nf + Nc) = errorSegment;
    errorSpectrum = fft(errorBlock, fftLength);

    % -- feedforward update (mu_f) -------------------------------------
    % Book: W(k+1) = W(k) + mu_f * F*G*F^H * (R_p0 .* E) / (eps + R^H R)
    % with the SCALAR block energy denominator; mu_f is the book's
    % frequency-domain step (0.2).
    denomF = 1e-6 + epsilon_norm(inputSpectrum);
    gradF = conj(inputSpectrum.') .* errorSpectrum.';
    W = W + muF * gradF / denomF;
    W = time_constrain(W, fftLength, Nf);

    % -- feedback update (mu_b) ----------------------------------------
    denomB = 1e-6 + epsilon_norm(feedbackSpectrum);
    gradB = conj(feedbackSpectrum.') .* errorSpectrum.';
    B = B + muB * gradB / denomB;
    B = time_constrain(B, fftLength, Nb);

    frontTail = current(end - Nf + 1:end);
    trace.weightNorm(block + 1) = norm(W) + norm(B);
    trace.errorPower(block + 1) = mean(abs(errorSegment(inFrame)).^2);
end
output = output(1:min(totalSamples, numBlocks * Nc));
% The frame is [training; data]: extract the equalized data segment
% (after the training symbols).
dataStart = min(trainLength + 1, numel(output));
dataSymbols = output(dataStart:end);
if isfield(cfg, "permutation") && ~isempty(cfg.permutation)
    % Coded frame: de-interleave the equalized BPSK symbols, run the
    % (7,5) BCJR decoder and output the information bits (consistent
    % with the other turbo equalizers in the unified entry).
    permutation = cfg.permutation;
    inversePermutation = zeros(1, numel(permutation));
    inversePermutation(permutation) = 1:numel(permutation);
    codedLlr = real(dataSymbols(1:numel(permutation))) * 2 / ...
        max(field_default(cfg, "noiseVariance", 1e-3), 1e-6);
    equalizerInput = codedLlr(inversePermutation);
    [informationLlr, ~] = scfde.equalizers.ch4_bcjr_siso_decode( ...
        equalizerInput, field_default(cfg, "turboDecoderMode", "Log-MAP"));
    bits = informationLlr < 0;
    decisions = 1 - 2 * bits;
else
    % Uncoded: output the equalized data symbols as-is.
    decisions = dataSymbols;
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
