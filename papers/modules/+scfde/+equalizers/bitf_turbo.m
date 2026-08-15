function receiver = bitf_turbo(channel, source, cfg)
%BITF_TURBO Bidirectional time-frequency Turbo equalizer module (spec 4.5).
% The scenario owns the interleaver; the module returns exactly 512
% information-symbol decisions and never resets the global RNG.
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
H = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
[bits, ~, trace] = scfde.equalizers.ch4_iterate_time_frequency_turbo( ...
    channel.received, fft(channel.received), [], [], H, H, ...
    cfg.noiseVariance, frame, cfg, true, false);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer("BiTF-Turbo-Log-MAP", ...
    "bitf-turbo", decisions, zeros(size(decisions)), decisions, trace);
end
