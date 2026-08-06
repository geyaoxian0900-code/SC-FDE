function [detected, scores] = ch5_backward_dfe_detect(received, book, channel, noiseVariance, limit)
reverseReceived = conj(fliplr(received));
reverseBook = conj(fliplr(book));
reverseChannel = conj(fliplr(channel));
[reverseDetected, reverseScores] = scfde.equalizers.ch5_dfe_detect(reverseReceived, reverseBook, ...
    reverseChannel, noiseVariance, limit);
detected = fliplr(reverseDetected);
scores = flipud(reverseScores);
end
