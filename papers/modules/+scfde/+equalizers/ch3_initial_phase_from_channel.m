function phase = ch3_initial_phase_from_channel(H)
impulse = ifft(H);
phase = angle(impulse(1));
end
