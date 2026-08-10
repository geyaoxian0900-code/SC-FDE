function receiver = fd_dfe(channel, source, cfg)
%FD_DFE Frequency-domain decision-feedback equalizer module (book 4.2).
% The scenario owns the interleaver (cfg.permutation); the module
% builds the validated Chapter-4 frame contract and returns exactly
% 512 information-symbol decisions.  The module never resets the
% global RNG.
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
H = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
[bits, ~, trace] = scfde.equalizers.ch4_frequency_dfe_baseline( ...
    fft(channel.received), H, cfg.noiseVariance, frame, cfg);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer("FD-DFE", "fd-dfe", ...
    decisions, zeros(size(decisions)), decisions, trace);
end
