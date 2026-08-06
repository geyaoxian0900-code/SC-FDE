function receiver = fd_dfe(channel, source, cfg)
%FD_DFE Frequency-domain decision-feedback equalizer module (book 4.2).
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
H = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
info = double(source.data < 0);
rng(2024, 'twister'); permutation = randperm(N);
inversePermutation = zeros(1, N);
inversePermutation(permutation) = 1:N;
[bits, ~, trace] = scfde.equalizers.ch4_frequency_dfe_baseline( ...
    fft(channel.received), H, cfg.noiseVariance, info, inversePermutation, cfg);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer("FD-DFE", "fd-dfe", ...
    decisions, zeros(size(decisions)), decisions, trace);
end
