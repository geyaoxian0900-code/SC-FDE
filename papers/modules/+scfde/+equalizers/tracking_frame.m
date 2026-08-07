function tracking = tracking_frame(uw, trueDoppler, fs, fc, ...
        samplesPerSymbol, dataLength, rngSeed)
%TRACKING_FRAME Build a per-block time-varying Doppler frame.
%   TRACKING = TRACKING_FRAME(UW, TRUEDOPPLER, FS, FC, SAMPLESPERSSYMBOL,
%   DATALENGTH, RNGSEED) builds one frame of numel(TRUEDOPPLER) blocks.
%   Each block carries its own four segments [pre-UW; pre-UW; data;
%   post-UW] and the WHOLE block (including both pre-UWs and the post-UW)
%   is stretched and carrier-shifted by that block's Doppler, so the
%   estimator's pre-UWs and post-UW of one block always experience the
%   same Doppler.  The carrier phase continues across the frame: the
%   saved phase is the NEXT sample's phase, so the first sample of the
%   next block advances by exactly one sample interval instead of
%   duplicating the boundary sample.
%
%   Returns TRACKING.received (the stretched+carrier waveform before the
%   channel), TRACKING.samplesPerSymbol, TRACKING.trueDoppler and
%   TRACKING.blockLayout (samples per segment, per block).
if nargin < 7
    rngSeed = 1;
end
rng(rngSeed, "twister");
blockCount = numel(trueDoppler);
uwSamples = repelem(uw(:), samplesPerSymbol);
preSamples = numel(uwSamples);                 % one pre-UW
dataSamples = dataLength * samplesPerSymbol;
blockLayout = [preSamples, preSamples, dataSamples, preSamples];
stretched = zeros(0, 1);
cumulativePhase = 0;
for block = 1:blockCount
    doppler = trueDoppler(block);
    bits = randi([0, 1], 2 * dataLength, 1);
    bitMatrix = reshape(bits, 2, []);
    data = ((1 - 2 * bitMatrix(1, :)) + ...
        1j * (1 - 2 * bitMatrix(2, :))).' / sqrt(2);
    blockSymbols = [uw(:); uw(:); data; uw(:)];
    blockSamples = repelem(blockSymbols, samplesPerSymbol);
    segmentLength = floor((numel(blockSamples) - 1) * ...
        (1 + doppler)) + 1;
    sourcePosition = (0:segmentLength-1).' / (1 + doppler) + 1;
    blockStretched = interp1((1:numel(blockSamples)).', ...
        blockSamples, sourcePosition, "linear", 0);
    % Carrier phase: continues from the previous block's final phase.
    % The saved phase is the NEXT sample's phase (one carrier frequency
    % step beyond the last sample).
    n = (0:numel(blockStretched)-1).';
    phase = cumulativePhase + 2 * pi * fc * doppler ./ fs .* n;
    blockStretched = blockStretched .* exp(1j * phase);
    cumulativePhase = phase(end) + 2 * pi * fc * doppler ./ fs;
    stretched = [stretched; blockStretched]; %#ok<AGROW>
end
tracking.received = stretched;
tracking.samplesPerSymbol = samplesPerSymbol;
tracking.trueDoppler = trueDoppler(:);
tracking.blockLayout = blockLayout;
end
