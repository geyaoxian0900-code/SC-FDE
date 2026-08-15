function merged = ch5_tr_diversity_combine(forwardSoft, reverseStream)
%CH5_TR_DIVERSITY_COMBINE Equal-weight merge of the two BiDFE soft
% outputs (book (5-57)):
%       y(k) = ( ytilde(k) + ytilde_e(k) ) / 2,
% with both branches restored to the SAME time order (chip index k).
%
%   FORWARDSOFT:   blockCount x 8 forward-branch soft chips in original
%                  block order (third output of ch5_dfe_detect), or an
%                  equivalent 1 x (8*blockCount) stream.
%   REVERSESTREAM: 1 x frameLength same-time-order reversed-branch
%                  stream from ch5_tr_diversity_restore; the first
%                  `memory` positions may be NaN (no reversed window
%                  exists there).
%
%   Output is the merged 1 x (8*blockCount) chip stream.  Chips whose
%   reversed-branch estimate is missing (NaN) take the forward branch
%   alone: the reversed window physically does not cover the frame
%   head, so no second term exists there.  This head rule is an
%   explicit ENGINEERING decision recorded in the wrapper trace.
if isvector(forwardSoft)
    forwardStream = forwardSoft(:).';
elseif isnumeric(forwardSoft) && ismatrix(forwardSoft) && ...
        size(forwardSoft, 2) == 8
    forwardStream = reshape(forwardSoft.', 1, []);
else
    error("SCFDE:TrDiversityCombineShape", ...
        "forwardSoft must be a blockCount-by-8 matrix or a row vector");
end
if ~isnumeric(reverseStream) || ~isvector(reverseStream)
    error("SCFDE:TrDiversityCombineShape", ...
        "reverseStream must be a numeric row vector");
end
reverseStream = reverseStream(:).';
dataLength = numel(forwardStream);
if numel(reverseStream) < dataLength
    error("SCFDE:TrDiversityCombineLength", ...
        "reverseStream must cover the forward stream length");
end
hasReverse = ~isnan(reverseStream(1:dataLength));
merged = forwardStream;
merged(hasReverse) = (forwardStream(hasReverse) + ...
    reverseStream(hasReverse)) / 2;
end
