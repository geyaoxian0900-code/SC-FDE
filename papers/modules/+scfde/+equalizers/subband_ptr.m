function output = subband_ptr(input, impulse, bandCount, regularization)
%SUBBAND_PTR Subarray passive time-reversal front end (book 2-48).
% Each frequency band applies the time-reversed channel as a matched
% filter (no inverse filtering): Y(f) * conj(H(f)). The regularization
% argument is accepted for interface compatibility but a pure PTR uses no
% division by |H|^2, matching Eq. (2-48): y_p(n) = sum_k h_k*(-n) (x) r_k(n).
input = input(:).';
fftLength = 2^nextpow2(numel(input) + numel(impulse) - 1);
spectrum = fft(input, fftLength);
channelSpectrum = fft([impulse, zeros(1, fftLength - numel(impulse))]);
outputSpectrum = spectrum .* conj(channelSpectrum);
output = ifft(outputSpectrum);
output = output(1:numel(input));
end
