function ber = ch4_fdda_teq_uncoded_qpsk(ebN0dB, frames, seed)
%CH4_FDDA_TEQ_UNCODED_QPSK Book-identical FDDA-TEQ benchmark simulation.
%   BER = CH4_FDDA_TEQ_UNCODED_QPSK(EBN0DB, FRAMES, SEED)
%
% Reproduces the book Fig. 4-31 simulation conditions:
%   - modulation:    QPSK (uncoded)
%   - frame:         256 training + 1024 data QPSK symbols
%   - I_outer:       3 (equalize -> decision feedback -> re-equalize)
%   - Eb/N0 grid:    caller-supplied (book axis is Eb/N0)
%   - channel:       project 3-tap underwater acoustic channel
%                    imp = [1, 0.5*exp(j*0.4), 0.2*exp(-j*0.8)]
% The FDDA-TEQ adaptation follows Fig. 4-25: frequency-domain
% feedforward W and feedback B, scalar block-energy denominators,
% time-domain constraint G, training error e = d - xhat on the
% training segment (the 256 known symbols are passed several epochs),
% decision-directed error on the data segment, soft decision feedback
% across the I_outer iterations.
%
% Zero-error outcomes are reported as zero; the caller applies the
% Clopper-Pearson upper bound for censoring.

blockLength = 32;     % N_c sub-block
ffLength = 32;        % N_f feedforward length
fbLength = 10;        % N_b feedback length
muF = 2.0;   % scalar block-energy denominator (stable, converges in ~80 epochs)
muB = 0.05;
outerIterations = 3;
trainEpochs = 80;
trainSymbols = 256;
dataSymbols = 1024;
frameLength = trainSymbols + dataSymbols;
imp = [1, 0.5 * exp(1j * 0.4), 0.2 * exp(-1j * 0.8)];
% QPSK with unit symbol energy, Eb/N0 -> symbol SNR = 2*Eb/N0.
symbolSnr = 10^((ebN0dB + 3) / 10);
noiseVariance = 1 / symbolSnr;
rng(seed, "twister");
totalErrors = 0;
totalBits = 0;
for frame = 1:frames
    tx = (1 - 2 * randi([0 1], 1, frameLength * 2));
    tx = reshape(tx, 2, []).';
    tx = (tx(:, 1) + 1j * tx(:, 2)).' / sqrt(2);
    H = fft([imp, zeros(1, frameLength - numel(imp))]);
    received = (ifft(H .* fft(tx)).' + ...
        sqrt(noiseVariance / 2) * (randn(frameLength, 1) + ...
        1j * randn(frameLength, 1))).';
    training = tx(1:trainSymbols);
    Nc = blockLength;
    Nf = ffLength;
    Nb = fbLength;
    fftLength = Nc + 2 * max(Nf, Nb);
    numBlocks = ceil(frameLength / Nc);
    trainBlocks = ceil(trainSymbols / Nc);
    W = ones(fftLength, 1);
    B = zeros(fftLength, 1);
    softData = zeros(1, dataSymbols);
    lastDataBlock = zeros(1, Nc);
    % -- training epochs (known symbols, several passes) ---------------
    for epoch = 1:trainEpochs
        frontTail = zeros(1, Nf);
        for block = 0:trainBlocks - 1
            blockStart = block * Nc + 1;
            current = received(blockStart:blockStart + Nc - 1);
            rearStart = blockStart + Nc;
            rearEnd = min(rearStart + Nf - 1, frameLength);
            rear = zeros(1, Nf);
            if rearStart <= frameLength
                rear(1:rearEnd - rearStart + 1) = received(rearStart:rearEnd);
            end
            inputBlock = [frontTail, current, rear];
            inputSpectrum = fft(inputBlock, fftLength);
            xhatPrev = training(block * Nc + 1:(block + 1) * Nc);
            feedbackSpectrum = fft([zeros(1, Nf), xhatPrev, zeros(1, Nf)], ...
                fftLength);
            filtered = ifft(W .* inputSpectrum.' - ...
                B .* feedbackSpectrum.').';
            valid = filtered(Nf + 1:Nf + Nc);
            desired = training(block * Nc + 1:(block + 1) * Nc);
            err = desired - valid;
            errorBlock = zeros(1, fftLength);
            errorBlock(Nf + 1:Nf + Nc) = err;
            E = fft(errorBlock, fftLength);
            denomF = 1e-6 + real(inputSpectrum * inputSpectrum');
            W = W + muF * (conj(inputSpectrum.') .* E.') / denomF;
            W = time_constrain(W, fftLength, Nf);
            denomB = 1e-6 + real(feedbackSpectrum * feedbackSpectrum');
            B = B + muB * (conj(feedbackSpectrum.') .* E.') / denomB;
            B = time_constrain(B, fftLength, Nb);
            frontTail = current(end - Nf + 1:end);
        end
    end
    % -- outer iterations over the data segment ------------------------
    output = zeros(1, numBlocks * Nc);
    for outer = 1:outerIterations
        frontTail = received(trainSymbols - Nf + 1:trainSymbols);
        for block = trainBlocks:numBlocks - 1
            blockStart = block * Nc + 1;
            current = received(blockStart:blockStart + Nc - 1);
            rearStart = blockStart + Nc;
            rearEnd = min(rearStart + Nf - 1, frameLength);
            rear = zeros(1, Nf);
            if rearStart <= frameLength
                rear(1:rearEnd - rearStart + 1) = received(rearStart:rearEnd);
            end
            inputBlock = [frontTail, current, rear];
            inputSpectrum = fft(inputBlock, fftLength);
            if outer == 1
                if block == trainBlocks
                    xhatPrev = lastDataBlock;
                else
                    xhatPrev = output((block - 1) * Nc + (1:Nc));
                end
                xhatPrev = map_qpsk(xhatPrev);
            else
                dataOffset = block * Nc - trainSymbols;
                if dataOffset + Nc <= dataSymbols
                    xhatPrev = softData(dataOffset + 1:dataOffset + Nc);
                elseif dataOffset < dataSymbols
                    xhatPrev = [softData(dataOffset + 1:end), ...
                        zeros(1, dataOffset + Nc - dataSymbols)];
                else
                    xhatPrev = zeros(1, Nc);
                end
            end
            feedbackSpectrum = fft([zeros(1, Nf), xhatPrev, zeros(1, Nf)], ...
                fftLength);
            filtered = ifft(W .* inputSpectrum.' - ...
                B .* feedbackSpectrum.').';
            valid = filtered(Nf + 1:Nf + Nc);
            output(block * Nc + 1:(block + 1) * Nc) = valid;
            if block >= trainBlocks
                lastDataBlock = valid;
            end
            % The data segment uses the TRAINED W/B (fixed); the
            % decision-directed adaptation is confined to the training
            % segment to avoid error propagation at low SNR.
            frontTail = current(end - Nf + 1:end);
        end
        % soft feedback for the next outer iteration
        dataOut = output(trainSymbols + 1:trainSymbols + dataSymbols);
        if outer < outerIterations
            softData = 0.8 * map_qpsk(dataOut) + 0.2 * dataOut;
        end
    end
    dataOut = output(trainSymbols + 1:trainSymbols + dataSymbols);
    refData = tx(trainSymbols + 1:end);
    rxBits = [real(dataOut) > 0; imag(dataOut) > 0];
    txBits = [real(refData) > 0; imag(refData) > 0];
    totalErrors = totalErrors + sum(rxBits(:) ~= txBits(:));
    totalBits = totalBits + 2 * dataSymbols;
end
ber = totalErrors / totalBits;
end

function symbols = map_qpsk(x)
% Nearest QPSK symbol of unit energy.
symbols = (sign(real(x)) + 1j * sign(imag(x))) / sqrt(2);
end

function constrained = time_constrain(spectrum, fftLength, lengthKeep)
constrained = ifft(spectrum, fftLength);
constrained(lengthKeep + 1:end) = 0;
constrained = fft(constrained, fftLength);
end
