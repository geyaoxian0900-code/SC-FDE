function receiver = blms_tf_turbo(channel, source, cfg)
%BLMS_TF_TURBO BLMS time-frequency Turbo equalizer module (spec 4.6).
% The scenario owns the interleaver; the module returns exactly 512
% information-symbol decisions and never resets the global RNG.  The
% per-bin BLMS channel adaptation is an ENGINEERING extension (spec 4.6
% requires the strict block FBLMS feedforward); recorded in the trace.
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
H = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
[bits, ~, trace] = scfde.equalizers.ch4_iterate_time_frequency_turbo( ...
    channel.received, fft(channel.received), [], [], H, H, ...
    cfg.noiseVariance, frame, cfg, false, true);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer("BLMS-TF-Turbo", ...
    "blms-tf-turbo", decisions, zeros(size(decisions)), decisions, trace);
end
