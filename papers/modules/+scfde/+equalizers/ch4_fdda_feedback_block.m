function feedbackBlock = ch4_fdda_feedback_block(estimates, blockStart0, ...
    blockLength, ffLength)
%CH4_FDDA_FEEDBACK_BLOCK Book Eq. (4-75) feedback block construction.
%   FEEDBACKBLOCK = CH4_FDDA_FEEDBACK_BLOCK(ESTIMATES, BLOCKSTART0, N, NF)
%
% The feedback block of block k is
%       Xtilde0(k) = [ decided symbols before block k ; 0_N ; decided
%                      symbols after block k ]
% with the middle N positions (the current block's own samples) set to
% ZERO: the feedback filter cancels inter-block interference coming
% from the NEIGHBOURING blocks only, not the current block's own
% symbols.
%
% ESTIMATES is the full decided/soft symbol sequence of the previous
% outer iteration (length >= BLOCKSTART0 + N + NF); BLOCKSTART0 is the
% zero-based sample offset of the first sample of block k inside
% ESTIMATES.  The first NF entries of the block are
% ESTIMATES(BLOCKSTART0-NF+1 .. BLOCKSTART0) and the last NF entries
% ESTIMATES(BLOCKSTART0+N+1 .. BLOCKSTART0+N+NF); out-of-range
% positions are zero (block/frame edges).
%
% The returned block has length N + 2*NF, matching the front/middle/
% rear structure of the input blocks.  For the FIRST turbo equalization
% (no prior information) the whole feedback block must be zero; callers
% pass zero estimates in that case.

N = blockLength;
Nf = ffLength;
feedbackBlock = zeros(1, N + 2 * Nf);
% -- past decisions: NF samples immediately before the block ----------
if blockStart0 - Nf >= 0
    feedbackBlock(1:Nf) = ...
        estimates(blockStart0 - Nf + 1:blockStart0);
else
    available = blockStart0;
    if available > 0
        feedbackBlock(Nf - available + 1:Nf) = estimates(1:available);
    end
end
% -- middle: the current block's own positions are ZERO (Eq. 4-75) ----
% (feedbackBlock(Nf+1:Nf+N) stays zero)
% -- future decisions: NF samples immediately after the block ---------
futureStart = blockStart0 + N;
if futureStart + Nf <= numel(estimates)
    feedbackBlock(N + Nf + 1:end) = ...
        estimates(futureStart + 1:futureStart + Nf);
else
    available = numel(estimates) - futureStart;
    if available > 0
        feedbackBlock(N + Nf + 1:N + Nf + available) = ...
            estimates(futureStart + 1:futureStart + available);
    end
end
end
