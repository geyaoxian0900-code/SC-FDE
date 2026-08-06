function receiver = tf_turbo(channel, source, cfg)
%TF_TURBO Time-frequency domain Turbo equalizer module (book 4.4.1).
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
H = fft([channel.impulse, zeros(1, N - numel(channel.impulse))]);
channelMatrix = scfde.equalizers.ch4_circulant_channel(channel.impulse, N);
timeEqualizer = (channelMatrix' * channelMatrix + ...
    cfg.noiseVariance * eye(N)) \ channelMatrix';
info = double(source.data < 0);
rng(2024, 'twister'); permutation = randperm(N);
inversePermutation = zeros(1, N);
inversePermutation(permutation) = 1:N;
[bits, ~, trace] = scfde.equalizers.ch4_iterate_time_frequency_turbo( ...
    channel.received, fft(channel.received), channelMatrix, ...
    timeEqualizer, H, H, cfg.noiseVariance, info, permutation, ...
    inversePermutation, cfg, false, false);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer("TF-Turbo-Log-MAP", ...
    "tf-turbo", decisions, zeros(size(decisions)), decisions, trace);
end
