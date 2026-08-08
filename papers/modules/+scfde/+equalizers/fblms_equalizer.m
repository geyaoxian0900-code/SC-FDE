function [output, weights, trace] = fblms_equalizer(received, ...
    reference, trainLength, filterLength, blockLength, step, epsilon, ...
    useDecisionFeedback, decisionFcn)
%FBLMS_EQUALIZER Frequency-domain block LMS equalizer (book Fig. 4-24).
%   [OUTPUT, WEIGHTS, TRACE] = FBLMS_EQUALIZER(RECEIVED, REFERENCE,
%   TRAINLENGTH, FILTERLENGTH, BLOCKLENGTH, STEP, EPSILON,
%   USEDECISIONFEEDBACK, DECISIONFCN)
%
% Implements the book's frequency-domain block adaptive equalizer with
% the front/middle/rear overlap-save structure:
%
%   input block:  y'_e(k) = [y((k-1)N-N_f+1) ... y((k-1)N+N+N_f)]
%                 = [front N_f overlap | middle N | rear N_f]
%   FFT length:   N + 2*N_f
%   time-domain constraint:
%                 G = [ I_{N_f} 0 0 ; 0 0 0 ; 0 0 0 ]  (3x3 block)
%   output pick:  T = [0_{N_f}; I_{N_e}; 0_{N_f}]  with N_e = N
%                 (front N_f and rear N_f samples are circular-
%                 convolution contamination and are dropped)
%   error:        e = x - xhat        during training (kN <= L_train)
%                 e = xtilde - xhat   otherwise (decision-directed)
%   update:       W(k+1) = W(k) + mu_f * F*G*F^H * (R_e*(k) .* E(k))
%                               / (eps + R_e^H(k)*R_e(k))
%   denominator:  SCALAR block energy (eps + sum_bin |R_e|^2), as in
%                 the book; mu_f is the adaptive step.
%
% DECISIONFCN is the modulation-matched hard-decision function used for
% the decision-directed error (e.g. a 4-quadrant unit-energy QPSK slicer
% or sign(real(...)) for BPSK); when omitted it defaults to BPSK
% sign(real(...)).  Zero-padded samples of the final partial block do
% NOT contribute to the update or the reported error power.
%
% The G constraint keeps the weight vector length N_f in the time
% domain, so the FFT-domain products correspond to linear convolution.
%
% OUTPUT is the valid equalized samples (N per block; front and rear
% contaminated samples dropped).  WEIGHTS is the final frequency-domain
% weight vector; TRACE holds per-block weight norms and error powers.

N = blockLength;
Nf = filterLength;
fftLength = N + 2 * Nf;
if nargin < 8
    useDecisionFeedback = false;
end
if nargin < 9 || isempty(decisionFcn)
    decisionFcn = @(values) bpsk_slice(values);
end

received = received(:).';
reference = reference(:).';
totalSamples = numel(received);
% Every input sample belongs to a block: ceil(totalSamples/N) blocks,
% the last one zero-padded.  The output is cropped to the original
% length.
numBlocks = ceil(totalSamples / N);
if numBlocks < 1
    error("SCFDE:FBLMS", "Signal too short for the requested block size.");
end

weights = zeros(fftLength, 1);
output = zeros(1, numBlocks * N);
trace.weightNorm = zeros(1, numBlocks);
trace.errorPower = zeros(1, numBlocks);

frontTail = zeros(1, Nf);   % front overlap from the previous block
for block = 0:numBlocks - 1
    % -- front/middle/rear input block --------------------------------
    blockStart = block * N + 1;
    blockEnd = min(blockStart + N - 1, totalSamples);
    current = received(blockStart:blockEnd);
    if numel(current) < N
        current = [current, zeros(1, N - numel(current))]; %#ok<AGROW>
    end
    % Rear overlap: the first Nf samples of the NEXT block (zero if the
    % frame ends there).
    rearStart = blockEnd + 1;
    rearEnd = min(rearStart + Nf - 1, totalSamples);
    rear = zeros(1, Nf);
    if rearStart <= totalSamples
        rear(1:rearEnd - rearStart + 1) = received(rearStart:rearEnd);
    end
    inputBlock = [frontTail, current, rear];
    inputSpectrum = fft(inputBlock, fftLength);

    % -- filtering (FFT-domain product = linear convolution) -----------
    filteredSpectrum = weights .* inputSpectrum.';
    filtered = ifft(filteredSpectrum, fftLength).';

    % -- valid samples: middle N (front/rear contamination dropped) ----
    validSegment = filtered(Nf + 1:Nf + N);
    output(block * N + 1:(block + 1) * N) = validSegment;

    % -- error ---------------------------------------------------------
    sampleIndex = block * N + (1:N);
    inFrame = sampleIndex <= totalSamples;
    % Per-sample training mask: a partial block whose tail lies inside
    % the training region still uses the reference symbols for those
    % in-frame training samples.
    trainingMask = inFrame & sampleIndex <= trainLength;
    desired = zeros(1, N);
    desired(trainingMask) = reference(sampleIndex(trainingMask));
    if ~all(trainingMask)
        % Samples outside the training region: decision-directed when
        % enabled, otherwise freeze the error (no update for those
        % samples; only the in-frame training contribution remains).
        if useDecisionFeedback
            decisions = decisionFcn(validSegment);
            desired(~trainingMask) = decisions(~trainingMask);
        else
            desired(~trainingMask) = validSegment(~trainingMask);
        end
    end
    errorSegment = desired - validSegment;
    % Zero-padded samples of the final partial block must not
    % contribute to the adaptive update or the reported error power.
    errorSegment(~inFrame) = 0;
    % The error block is zero-padded to the FFT length; its N samples
    % occupy the positions aligned with the valid (middle) output.
    errorBlock = zeros(1, fftLength);
    errorBlock(Nf + 1:Nf + N) = errorSegment;
    errorSpectrum = fft(errorBlock, fftLength);

    % -- NLMS update with time-domain constraint G ---------------------
    % The book's denominator is the SCALAR block energy
    %   epsilon + R_e^H(k) * R_e(k) = epsilon + sum_bin |R_e|^2
    % and mu_f = step * fftLength scales the normalized update so that
    % `step` has the usual NLMS step meaning (0..1); the book's mu_f is
    % the frequency-domain block step.
    blockEnergy = real(inputSpectrum * inputSpectrum'); % scalar
    gradient = conj(inputSpectrum.') .* errorSpectrum.';
    update = step * fftLength * gradient / (epsilon + blockEnergy);
    weights = weights + update;
    % time-domain constraint: keep only the first Nf taps
    constrained = ifft(weights, fftLength);
    constrained(Nf + 1:end) = 0;
    weights = fft(constrained, fftLength);

    frontTail = current(end - Nf + 1:end);
    trace.weightNorm(block + 1) = norm(weights);
    trace.errorPower(block + 1) = mean(abs(errorSegment(inFrame)).^2);
end
% Crop the output back to the original signal length.
output = output(1:totalSamples);
end

function symbols = bpsk_slice(values)
symbols = sign(real(values));
symbols(symbols == 0) = 1;
end
