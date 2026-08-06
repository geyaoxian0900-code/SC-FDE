function receiver = fd_turbo(channel, source, cfg)
%FD_TURBO Frequency-domain Turbo equalizer module (book 4-50~4-58).
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
H = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
info = double(source.data < 0);
rng(2024, 'twister'); permutation = randperm(N);
inversePermutation = zeros(1, N);
inversePermutation(permutation) = 1:N;
[bits, ~, trace] = scfde.equalizers.ch4_iterate_frequency_turbo( ...
    fft(channel.received), H, H, cfg.noiseVariance, info, ...
    permutation, inversePermutation, cfg, cfg.turboDecoderMode, false);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer( ...
    "FD-Turbo-" + cfg.turboDecoderMode, "fd-turbo", decisions, ...
    zeros(size(decisions)), decisions, trace);
end
