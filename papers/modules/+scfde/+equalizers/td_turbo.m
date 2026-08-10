function receiver = td_turbo(channel, source, cfg)
%TD_TURBO Time-domain Turbo equalizer module (book 4.1 BCJR + LMMSE).
% The scenario owns the interleaver (cfg.permutation); the module
% builds the validated Chapter-4 frame contract and returns exactly
% 512 information-symbol decisions.  The module never resets the
% global RNG.
% decoderMode in cfg.turboDecoderMode: "MAP", "Log-MAP", "Max-Log-MAP".
N = numel(channel.received);
cfg = scfde.equalizers.ch4_setup(cfg, N);
frame = scfde.equalizers.ch4_turbo_frame_contract(channel, source, cfg);
channelMatrix = scfde.equalizers.ch4_circulant_channel(channel.impulse, N);
timeEqualizer = (channelMatrix' * channelMatrix + ...
    cfg.noiseVariance * eye(N)) \ channelMatrix';
[bits, ~, trace] = scfde.equalizers.ch4_iterate_time_turbo( ...
    channel.received, channelMatrix, timeEqualizer, cfg.noiseVariance, ...
    frame, cfg, cfg.turboDecoderMode);
decisions = 1 - 2 * bits;
receiver = scfde.equalizers.pack_equalizer( ...
    "TD-Turbo-" + cfg.turboDecoderMode, "td-turbo", decisions, ...
    zeros(size(decisions)), decisions, trace);
end
