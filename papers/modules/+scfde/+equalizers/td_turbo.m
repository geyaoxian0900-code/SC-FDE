function receiver = td_turbo(channel, source, cfg)
%TD_TURBO Time-domain Turbo equalizer module (book 4.1 BCJR + LMMSE).
% decoderMode in cfg.turboDecoderMode: "MAP", "Log-MAP", "Max-Log-MAP".
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
channelMatrix = scfde.equalizers.ch4_circulant_channel(channel.impulse, N);
timeEqualizer = (channelMatrix' * channelMatrix + ...
    cfg.noiseVariance * eye(N)) \ channelMatrix';
info = double(source.data(1:min(cfg.infoBits, numel(source.data))) < 0);
rng(2024, 'twister'); permutation = randperm(N);
inversePermutation = zeros(1, N);
inversePermutation(permutation) = 1:N;
[bits, ~, trace] = scfde.equalizers.ch4_iterate_time_turbo( ...
    channel.received, channelMatrix, timeEqualizer, cfg.noiseVariance, ...
    info, permutation, inversePermutation, cfg, cfg.turboDecoderMode);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer( ...
    "TD-Turbo-" + cfg.turboDecoderMode, "td-turbo", decisions, ...
    zeros(size(decisions)), decisions, trace);
end
