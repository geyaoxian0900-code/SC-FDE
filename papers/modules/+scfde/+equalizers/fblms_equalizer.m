function [output, weights, trace] = fblms_equalizer(received, ...
    reference, trainLength, filterLength, blockLength, step, epsilon, ...
    useDecisionFeedback)
%FBLMS_EQUALIZER Frequency-domain block LMS equalizer (book Fig. 4-25).
%   [OUTPUT, WEIGHTS, TRACE] = FBLMS_EQUALIZER(RECEIVED, REFERENCE,
%   TRAINLENGTH, FILTERLENGTH, BLOCKLENGTH, STEP, EPSILON,
%   USEDECISIONFEEDBACK)
%
% Implements the book's frequency-domain block adaptive equalizer with
% strict overlap-save (linear-convolution) semantics:
%
%   input block:  y'_e(k) = [y((k-1)N-N_f+1) ... y((k-1)N)]
%                 (N_f samples of overlap from the previous block)
%   FFT length:   N + N_f
%   time-domain constraint G = blkdiag(I_{N_f}, 0_N)
%   output pick:  T = [0_{N_f}; I_N]  (first N_f samples are
%                 circular-convolution contamination and are dropped)
%   error:        e = x - xhat        during training (kN <= L_train)
%                 e = xtilde - xhat   otherwise (decision-directed)
%   update:       W(k+1) = W(k) + mu_f * F*G*F^H * (R_c*(k) .* E(k))
%                               / (eps + R_c^H(k)*R_c(k))
%
% The G constraint keeps the weight vector length N_f in the time
% domain, so the FFT-domain products correspond to linear convolution.
%
% OUTPUT is the valid equalized samples (N per block, first N_f
% contaminated samples of every block dropped).  WEIGHTS is the final
% frequency-domain weight vector; TRACE holds per-block weight norms
% and error powers.

N = blockLength;
Nf = filterLength;
fftLength = N + Nf;
if nargin < 8
    useDecisionFeedback = false;
end

received = received(:).';
reference = reference(:).';
totalSamples = numel(received);
% The implementation provides the initial overlap with previousTail =
% zeros(1,Nf) and reads from the first input sample, so every input
% sample belongs to a block: ceil(totalSamples/N) blocks, the last one
% zero-padded.  The output is cropped back to the original length.
numBlocks = ceil(totalSamples / N);
if numBlocks < 1
    error("SCFDE:FBLMS", "Signal too short for the requested block size.");
end

weights = zeros(fftLength, 1);
output = zeros(1, numBlocks * N);
trace.weightNorm = zeros(1, numBlocks);
trace.errorPower = zeros(1, numBlocks);

previousTail = zeros(1, Nf);
for block = 0:numBlocks - 1
    % -- overlap-save input block: [previous Nf samples, current N] ----
    blockStart = block * N + 1;
    blockEnd = min(blockStart + N - 1, totalSamples);
    current = received(blockStart:blockEnd);
    if numel(current) < N
        current = [current, zeros(1, N - numel(current))]; %#ok<AGROW>
    end
    inputBlock = [previousTail, current];
    inputSpectrum = fft(inputBlock, fftLength);

    % -- filtering (FFT-domain product = linear convolution) -----------
    filteredSpectrum = weights .* inputSpectrum.';
    filtered = ifft(filteredSpectrum, fftLength).';

    % -- valid samples: drop the first Nf contaminated samples ---------
    validSegment = filtered(Nf + 1:Nf + N);
    output(block * N + 1:(block + 1) * N) = validSegment;

    % -- error ---------------------------------------------------------
    sampleIndex = block * N + (1:N);
    inFrame = sampleIndex <= totalSamples;
    if block * N + N <= trainLength
        desired = zeros(1, N);
        desired(inFrame) = reference(sampleIndex(inFrame));
    elseif useDecisionFeedback
        desired = sign(real(validSegment));
        desired(desired == 0) = 1;
    else
        desired = validSegment;
    end
    errorSegment = desired - validSegment;
    % The error block is zero-padded to the FFT length; its N samples
    % occupy the positions aligned with the valid output segment.
    errorBlock = zeros(1, fftLength);
    errorBlock(Nf + 1:Nf + N) = errorSegment;
    errorSpectrum = fft(errorBlock, fftLength);

    % -- NLMS update with time-domain constraint G ---------------------
    % Per-bin NLMS normalization (epsilon + |R_c(k)|^2) is used so the
    % gradient is well scaled bin by bin; the time-domain constraint G
    % (keep only the first Nf taps) keeps the FFT-domain products
    % equivalent to linear convolution and bounds the weight growth.
    gradient = conj(inputSpectrum.') .* errorSpectrum.';
    denominator = epsilon + abs(inputSpectrum.').^2;
    update = step * gradient ./ denominator;
    weights = weights + update;
    % time-domain constraint: keep only the first Nf taps
    constrained = ifft(weights, fftLength);
    constrained(Nf + 1:end) = 0;
    weights = fft(constrained, fftLength);

    previousTail = current(end - Nf + 1:end);
    trace.weightNorm(block + 1) = norm(weights);
    trace.errorPower(block + 1) = mean(abs(errorSegment).^2);
end
% Crop the output back to the original signal length.
output = output(1:totalSamples);
end
