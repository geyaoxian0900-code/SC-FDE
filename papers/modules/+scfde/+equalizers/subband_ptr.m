function output = subband_ptr(input, impulse, bandCount, regularization)
%SUBBAND_PTR Shared subband passive time-reversal front end (2-48).
input = input(:).';
fftLength = 2^nextpow2(numel(input) + numel(impulse) - 1);
spectrum = fft(input, fftLength);
channelSpectrum = fft([impulse, zeros(1, fftLength - numel(impulse))]);
outputSpectrum = zeros(1, fftLength);
frequency = (0:fftLength - 1) / fftLength;
for bandIndex = 1:bandCount
    mask = frequency >= (bandIndex - 1) / bandCount & ...
        frequency < bandIndex / bandCount;
    if bandIndex == bandCount
        mask = frequency >= (bandIndex - 1) / bandCount;
    end
    outputSpectrum(mask) = spectrum(mask) .* conj(channelSpectrum(mask)) ./ ...
        (abs(channelSpectrum(mask)).^2 + regularization);
end
output = ifft(outputSpectrum);
output = output(1:numel(input));
end
