function receiver = fdda_dfe_teq(channel, source, cfg)
%FDDA_DFE_TEQ Frequency-domain direct adaptive DFE turbo equalizer (4.5.3).
% The scenario owns the interleaver; the module returns exactly 512
% information-symbol decisions and never resets the global RNG.
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
Hinitial = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
[bits, ~, trace] = scfde.equalizers.ch4_iterate_fd_blms_turbo( ...
    fft(channel.received), Hinitial, Hinitial, cfg.noiseVariance, ...
    frame, cfg, true);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer("FDDA-DFE-TEQ", ...
    "fdda-dfe-teq", decisions, zeros(size(decisions)), decisions, trace);
end
