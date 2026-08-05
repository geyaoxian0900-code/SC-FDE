function output = apply_multipath(input, gains, delays, dopplerHz, sampleRate)
%APPLY_MULTIPATH Apply discrete delays and a common Doppler phase ramp.

output = zeros(size(input));
sampleIndex = 0:numel(input)-1;
for pathIndex = 1:numel(gains)
    delay = delays(pathIndex);
    delayed = zeros(size(input));
    if delay == 0
        delayed = input;
    elseif delay < numel(input)
        delayed(delay + 1:end) = input(1:end-delay);
    end
    phase = exp(1j * 2 * pi * dopplerHz * sampleIndex / sampleRate);
    output = output + gains(pathIndex) * delayed .* phase;
end
end
