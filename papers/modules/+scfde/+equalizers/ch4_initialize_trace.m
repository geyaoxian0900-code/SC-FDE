function trace = initialize_trace(iterations, blockLength, initialChannel)
trace.equalizerLlr = zeros(iterations, blockLength);
trace.decoderLlr = zeros(iterations, blockLength);
trace.reliability = zeros(1, iterations);
trace.channelNmse = nan(1, iterations);
trace.weightNmse = nan(1, iterations);
trace.errorPower = nan(1, iterations);
trace.frequencyWeights = complex(zeros(iterations, blockLength));
trace.initialChannel = initialChannel;
trace.finalChannel = initialChannel;
end
