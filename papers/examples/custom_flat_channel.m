function channel = custom_flat_channel(input, cfg)
%CUSTOM_FLAT_CHANNEL Example replacement channel with phase rotation.

phase = exp(1j * 0.2);
received = scfde.add_awgn(phase * input, cfg.snrDb);
channel.received = received;
channel.branches = [received; received];
channel.impulse = phase;
end
