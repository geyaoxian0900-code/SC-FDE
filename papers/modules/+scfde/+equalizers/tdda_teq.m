function receiver = tdda_teq(channel, source, cfg)
%TDDA_TEQ Time-domain direct adaptive turbo equalizer module (book 4.5.2).
% The scenario owns the interleaver; the module returns exactly 512
% information-symbol decisions and never resets the global RNG.
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
Hinitial = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
[bits, ~, trace] = scfde.equalizers.ch4_iterate_td_nlms_turbo( ...
    channel.received, fft(channel.received), Hinitial, Hinitial, ...
    cfg.noiseVariance, frame, cfg);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer("TDDA-TEQ", "tdda-teq", ...
    decisions, zeros(size(decisions)), decisions, trace);
end
