function channel = ch5_long_uwa_channel()
delays = [0, 1, 2, 3, 4, 5, 7, 9, 11, 13, 15];
power = exp(-delays / 5.5);
phase = [0, .5, -1.0, .8, -2.1, .25, -1.5, 1.4, -.8, .9, -2.6];
channel = zeros(1, delays(end) + 1);
channel(delays + 1) = sqrt(power) .* exp(1j * phase);
channel = channel / norm(channel);
end
