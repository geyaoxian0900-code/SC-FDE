function trace = ch4_save_trace(trace, iteration, equalizerLlr, decoderLlr, ...
        softSymbols, channelNmse)
trace.equalizerLlr(iteration, :) = equalizerLlr;
trace.decoderLlr(iteration, :) = decoderLlr;
trace.reliability(iteration) = mean(abs(softSymbols).^2);
if ~isempty(channelNmse)
    trace.channelNmse(iteration) = channelNmse;
end
end
