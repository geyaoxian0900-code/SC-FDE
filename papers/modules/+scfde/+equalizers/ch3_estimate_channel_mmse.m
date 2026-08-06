function H = ch3_estimate_channel_mmse(receivedTraining, training, ...
        channelLength, noiseVariance, priorVariance)
N = numel(training);
trainingSpectrum = fft(training);
receivedSpectrum = fft(receivedTraining);
if isempty(priorVariance)
    Hls = scfde.equalizers.ch3_estimate_channel_ls(receivedTraining, training, channelLength);
    priorVariance = max(mean(abs(Hls).^2), eps);
end
estimate = priorVariance * conj(trainingSpectrum) .* receivedSpectrum ./ ...
    (priorVariance * abs(trainingSpectrum).^2 + N * noiseVariance);
impulse = ifft(estimate);
impulse(channelLength + 1:end) = 0;
H = fft(impulse);
end
