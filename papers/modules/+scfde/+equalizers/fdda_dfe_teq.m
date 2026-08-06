function receiver = fdda_dfe_teq(channel, source, cfg)
%FDDA_DFE_TEQ Frequency-domain direct adaptive DFE turbo equalizer (4.5.3).
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
Hinitial = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
info = double(source.data < 0);
rng(2024, 'twister'); permutation = randperm(N);
inversePermutation = zeros(1, N);
inversePermutation(permutation) = 1:N;
[bits, ~, trace] = scfde.equalizers.ch4_iterate_fd_blms_turbo( ...
    fft(channel.received), Hinitial, Hinitial, cfg.noiseVariance, ...
    info, permutation, inversePermutation, cfg, true);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer("FDDA-DFE-TEQ", ...
    "fdda-dfe-teq", decisions, zeros(size(decisions)), decisions, trace);
end
