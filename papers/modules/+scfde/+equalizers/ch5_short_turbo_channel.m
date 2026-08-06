function channel = ch5_short_turbo_channel()
channel = [1, .70 * exp(1j * .4), .50 * exp(-1j * .8), ...
    .28 * exp(1j * 1.4), .15 * exp(-1j * 2.1)];
channel = channel / norm(channel);
end
