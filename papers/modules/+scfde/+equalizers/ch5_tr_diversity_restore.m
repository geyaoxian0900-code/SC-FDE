function restored = ch5_tr_diversity_restore(backwardSoft, frameLength, memory)
%CH5_TR_DIVERSITY_RESTORE Restore the reversed-branch soft output to the
% original time order for the (5-57) merge.
%
%   BACKWARDSOFT is the RAW reversed-domain soft matrix from
%   ch5_backward_dfe_detect: row j is the reversed-stream window of
%   reversed block j (which observes ORIGINAL block N-j+1).  Window
%   position i of row j carries the reversed-domain value
%       soft_j(i) = conj(r(k)) - stateRev(i),   k = frameLength - 8*j + 9 - i,
%   where r(k) is the received response sample that estimates original
%   chip k, and stateRev(i) is the reversed-domain spill of the
%   following original block.  The book reversal convention is
%   rev[] = conj(fliplr), so the same-time-order value for chip k is
%   conj(soft_j(i)).  Row j therefore covers original chips
%       k = frameLength - 8*j + 1 .. frameLength - 8*j + 8
%   (the response TAIL segment of block N-j+1).
%
%   FRAMELENGTH is numel(received) and MEMORY is numel(channel)-1.  For
%   the scenario frame convention (frameLength = data + memory tail
%   samples) the reversed windows jointly cover chips
%   memory+1 .. frameLength; the first `memory` chips of the frame have
%   no reversed-branch window and remain NaN.  For frames without a
%   tail (frameLength = 8*blockCount) the coverage is complete.
%
%   Output is a 1 x frameLength row, NaN where no reversed window
%   exists.  The (5-57) combiner uses the NaN mask to fall back to the
%   forward branch on the frame head (documented ENGINEERING rule).
if ~isnumeric(backwardSoft) || ~ismatrix(backwardSoft) || ...
        size(backwardSoft, 2) ~= 8
    error("SCFDE:TrDiversityRestoreShape", ...
        "backwardSoft must be a numeric blockCount-by-8 matrix");
end
blockCount = size(backwardSoft, 1);
if ~isscalar(frameLength) || ~isreal(frameLength) || ...
        frameLength < 8 * blockCount
    error("SCFDE:TrDiversityRestoreLength", ...
        "frameLength must be a real scalar >= 8 * blockCount");
end
if ~isscalar(memory) || ~isreal(memory) || memory < 0 || ...
        memory > frameLength
    error("SCFDE:TrDiversityRestoreMemory", ...
        "memory must be a real scalar in [0, frameLength]");
end
restoredRows = conj(fliplr(backwardSoft));
restored = nan(1, frameLength);
for j = 1:blockCount
    k0 = frameLength - 8 * j + 1;
    restored(k0:k0 + 7) = restoredRows(j, :);
end
end
