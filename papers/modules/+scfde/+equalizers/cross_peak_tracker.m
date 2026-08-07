function estimates = cross_peak_tracker(received, uw, samplesPerSymbol, ...
        blockLength, blockCount)
%CROSS_PEAK_TRACKER UW cross-correlation Doppler tracker (Eq. 3-8 form).
%   ESTIMATES = CROSS_PEAK_TRACKER(RECEIVED, UW, SAMPLESPERSSYMBOL,
%   BLOCKLENGTH, BLOCKCOUNT) locates both the pre-UW and the post-UW
%   correlation peaks INSIDE each block and computes
%       a_b = (postPeak_b - prePeak_b - postOffset) / postOffset
%   with postOffset = blockLength * samplesPerSymbol.  Both peaks belong
%   to the same block, so the estimate is fully independent of the other
%   blocks.  Parabolic interpolation around the integer peaks resolves
%   Doppler steps below one sample.
%
%   The frame must be built block by block as
%   [pre-UW; pre-UW; data; post-UW] with the whole block stretched and
%   carrier-shifted by the block's own Doppler (see tracking_frame).
uwSamples = repelem(uw(:), samplesPerSymbol);
blockSamples = blockLength * samplesPerSymbol;
blockStride = blockSamples + numel(uwSamples); % one full block
postOffset = blockSamples; % post-UW sits 2*uw+data after block start
prePeaks = zeros(blockCount, 1);
postPeaks = zeros(blockCount, 1);
nominalBlock = zeros(blockCount, 1);
nominalBlock(1) = 1;
for block = 1:blockCount
    if block > 1
        nominalBlock(block) = nominalBlock(block - 1) + blockStride;
    end
    windowHalf = round(numel(uwSamples) / 2);
    % Pre-UW peak: around the block start (drift covers the
    % accumulated stretch of the earlier blocks).
    drift = round((block - 1) * blockStride * 2e-3);
    preRange = nominalBlock(block) + (-drift - windowHalf:...
        drift + windowHalf);
    preRange = preRange(preRange >= 1 & ...
        preRange <= numel(received) - numel(uwSamples));
    correlation = zeros(size(preRange));
    for index = 1:numel(preRange)
        window = received(preRange(index):preRange(index) + ...
            numel(uwSamples) - 1);
        correlation(index) = abs(sum(window .* conj(uwSamples)));
    end
    [~, peakOffset] = max(correlation);
    prePeaks(block) = preRange(peakOffset);
    % Sub-sample refinement by parabolic interpolation around the
    % integer peak so the in-block spacing resolves Doppler steps below
    % one sample (postOffset ~ 6912 samples, 1 sample = 1.45e-4).
    if peakOffset > 1 && peakOffset < numel(correlation)
        y0 = correlation(peakOffset - 1);
        y1 = correlation(peakOffset);
        y2 = correlation(peakOffset + 1);
        denom = y0 - 2 * y1 + y2;
        if abs(denom) > eps
            prePeaks(block) = preRange(peakOffset) + ...
                0.5 * (y0 - y2) / denom;
        end
    end
    % Post-UW peak: postOffset samples after the pre-UW peak, with a
    % window covering the block-internal stretch.
    postRange = prePeaks(block) + postOffset + (-windowHalf:windowHalf);
    postRange = postRange(round(postRange) >= 1 & ...
        round(postRange) <= numel(received) - numel(uwSamples));
    correlation = zeros(size(postRange));
    for index = 1:numel(postRange)
        window = received(round(postRange(index)):round(postRange(index)) + ...
            numel(uwSamples) - 1);
        correlation(index) = abs(sum(window .* conj(uwSamples)));
    end
    [~, peakOffset] = max(correlation);
    postPeaks(block) = postRange(peakOffset);
    if peakOffset > 1 && peakOffset < numel(correlation)
        y0 = correlation(peakOffset - 1);
        y1 = correlation(peakOffset);
        y2 = correlation(peakOffset + 1);
        denom = y0 - 2 * y1 + y2;
        if abs(denom) > eps
            postPeaks(block) = postRange(peakOffset) + ...
                0.5 * (y0 - y2) / denom;
        end
    end
end
estimates = (postPeaks - prePeaks - postOffset) / postOffset;
end
