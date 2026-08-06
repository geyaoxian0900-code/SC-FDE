function receiver = htfde(channel, source, cfg)
%HTFDE Hybrid time-frequency domain equalizer module (book 3-61/3-62).
N = numel(channel.received);
cfg = scfde.equalizers.ch3_setup(cfg, N, numel(source.data));
uw = scfde.equalizers.ch3_zadoff_chu(cfg.uwLength, 1);
H = fft([channel.impulse(:).', zeros(1, N - numel(channel.impulse))]);
[symbols, trace] = scfde.equalizers.ch3_htfde_equalize( ...
    channel.received, H, cfg.noiseVariance, uw, cfg);
decisions = scfde.equalizers.ch3_qpsk_map( ...
    scfde.equalizers.ch3_qpsk_demap(symbols(1:cfg.dataSymbols)));
receiver = scfde.equalizers.pack_equalizer("HTFDE", "htfde", ...
    decisions, abs(symbols(1:cfg.dataSymbols) - source.data).^2, ...
    symbols(1:cfg.dataSymbols), trace);
end
