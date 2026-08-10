function [bits, decoderLlrFrame, softFrame, informationLlr, codedLlr] = ...
        ch4_decoder_feedback_frame(equalizerLlr, frame, ...
        previousSoftFrame, damping, decoderMode)
%CH4_DECODER_FEEDBACK_FRAME BCJR slicing and full-frame feedback rebuild.
%   [BITS, DECODERLLRFRAME, SOFTFRAME, INFORMATIONLLR, CODEDLLR] = ...
%       CH4_DECODER_FEEDBACK_FRAME(EQUALIZERLLR, FRAME, PREVIOUSSOFTFRAME, ...
%       DAMPING, DECODERMODE)
%
% The equalizer LLR covers the FULL 1280-symbol frame; only the 1024
% coded-data positions are fed to the (7,5) BCJR decoder (the 256
% training symbols never enter BCJR), which returns exactly 512
% information LLRs.  The full-frame feedback is rebuilt in transmitted
% order:
%   - decoderLlrFrame: the decoder extrinsic LLR on the data positions
%     (zero on the training positions);
%   - softFrame:       damped soft symbols, training positions locked
%     to the known training symbols;
%   - bits:            512 hard information decisions (logical).
% All row-vector outputs use the transmitted frame order; only the
% internal BCJR input uses the original (de-interleaved) coded order.

equalizerLlr = equalizerLlr(:).';
previousSoftFrame = previousSoftFrame(:).';
if numel(equalizerLlr) ~= frame.frameLength || ...
        numel(previousSoftFrame) ~= frame.frameLength
    error("SCFDE:TurboFrame", ...
        "Equalizer LLR and feedback frame must have %d elements.", ...
        frame.frameLength);
end
dataLlrTxOrder = equalizerLlr(frame.dataIndices);
decoderInput = dataLlrTxOrder(frame.inversePermutation);
[informationLlr, codedLlr] = ...
    scfde.equalizers.ch4_bcjr_siso_decode(decoderInput, decoderMode);
if numel(informationLlr) ~= frame.informationLength || ...
        numel(codedLlr) ~= frame.codedLength
    error("SCFDE:TurboDecoder", ...
        "BCJR returned %d information and %d coded LLRs.", ...
        numel(informationLlr), numel(codedLlr));
end
extrinsicOriginalOrder = codedLlr - decoderInput;
extrinsicTxOrder = extrinsicOriginalOrder(frame.permutation);
posteriorTxOrder = codedLlr(frame.permutation);
candidate = tanh(posteriorTxOrder / 2);
softFrame = previousSoftFrame;
softFrame(frame.trainingIndices) = frame.trainingSymbols;
softFrame(frame.dataIndices) = ...
    (1 - damping) * previousSoftFrame(frame.dataIndices) + damping * candidate;
decoderLlrFrame = zeros(1, frame.frameLength);
decoderLlrFrame(frame.dataIndices) = extrinsicTxOrder;
bits = informationLlr < 0;
end
