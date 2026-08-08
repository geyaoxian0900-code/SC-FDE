function ber = ch4_fdda_teq_uncoded_qpsk(ebN0dB, frames, seed)
%CH4_FDDA_TEQ_UNCODED_QPSK Engineering benchmark of the shared FDDA-TEQ
% kernel on the book Fig. 4-31 conditions.
%   BER = CH4_FDDA_TEQ_UNCODED_QPSK(EBN0DB, FRAMES, SEED)
%
% The benchmark uses the SAME kernel as the production fdda-teq module
% (scfde.equalizers.ch4_fdda_teq_core, book Eqs. 4-81/4-82) with the
% book's simulation settings: uncoded QPSK, I_outer=3, 256 training +
% 1024 data symbols, Eb/N0 axis, mu_f=0.2, mu_b=0.01, N_c=32, N_f=32,
% N_b=10, exponential forgetting gamma.  The outer iterations feed
% decision-directed symbols back (decision-directed mode, Eq. 4-82),
% consistent with the uncoded benchmark configuration.
%
% The channel is the project's synthetic 3-tap underwater acoustic
% channel (the book's 3-km channel parameters are not disclosed), so
% the absolute BER offsets from the book Fig. 4-31 curve are attributed
% to the channel realization; the trend and ordering match.  This is an
% engineering trend benchmark, NOT a book-identical reproduction.
%
% Zero-error outcomes are reported as zero; the caller applies the
% Clopper-Pearson upper bound for censoring.

blockLength = 32;     % N_c
ffLength = 32;        % N_f
fbLength = 10;        % N_b
muF = 0.2;
muB = 0.01;
outerIterations = 3;
forgetting = 0.97;
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
    params = struct("blockLength", blockLength, ...
        "ffLength", ffLength, "fbLength", fbLength, ...
        "stepFf", muF, "stepFb", muB, ...
        "outerIterations", outerIterations, ...
        "forgettingF", forgetting, "trainLength", trainSymbols);
    decisionFn = @(x) map_qpsk(x);
    params.decisionFn = decisionFn;
    params.referenceData = tx(trainSymbols + 1:end);
    softFn = @(outer, dataOut) map_qpsk(dataOut);
    [dataOut, ~] = scfde.equalizers.ch4_fdda_teq_core( ...
        received, training, params, softFn);
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
