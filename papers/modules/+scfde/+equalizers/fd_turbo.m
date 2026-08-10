function receiver = fd_turbo(channel, source, cfg)
%FD_TURBO Frequency-domain Turbo equalizer module (book 4-50~4-58).
% The scenario owns the interleaver (cfg.permutation); the module
% builds the validated Chapter-4 frame contract and returns exactly
% 512 information-symbol decisions.  The module never resets the
% global RNG.
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
H = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
[bits, ~, trace] = scfde.equalizers.ch4_iterate_frequency_turbo( ...
    fft(channel.received), H, H, cfg.noiseVariance, frame, cfg, ...
    cfg.turboDecoderMode, false);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer( ...
    "FD-Turbo-" + cfg.turboDecoderMode, "fd-turbo", decisions, ...
    zeros(size(decisions)), decisions, trace);
end
