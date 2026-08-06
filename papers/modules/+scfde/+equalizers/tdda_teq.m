function receiver = tdda_teq(channel, source, cfg)
%TDDA_TEQ Time-domain direct adaptive turbo equalizer module (book 4.5.2).
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
Hinitial = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
info = double(source.data < 0);
rng(2024, 'twister'); permutation = randperm(N);
inversePermutation = zeros(1, N);
inversePermutation(permutation) = 1:N;
[bits, ~, trace] = scfde.equalizers.ch4_iterate_td_nlms_turbo( ...
    channel.received, fft(channel.received), Hinitial, Hinitial, ...
    cfg.noiseVariance, info, permutation, inversePermutation, cfg);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer("TDDA-TEQ", "tdda-teq", ...
    decisions, zeros(size(decisions)), decisions, trace);
end
