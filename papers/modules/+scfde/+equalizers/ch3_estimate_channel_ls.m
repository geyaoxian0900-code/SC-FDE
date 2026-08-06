function H = ch3_estimate_channel_ls(receivedTraining, training, channelLength)
N = numel(training);
trainingSpectrum = fft(training);
receivedSpectrum = fft(receivedTraining);
estimate = receivedSpectrum .* conj(trainingSpectrum) ./ ...
    max(abs(trainingSpectrum).^2, eps);
impulse = ifft(estimate);
impulse(channelLength + 1:end) = 0;
H = fft(impulse);
end
