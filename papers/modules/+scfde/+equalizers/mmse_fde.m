function receiver = mmse_fde(channel, source, cfg)
%MMSE_FDE Frequency-domain MMSE equalizer module (book 3-26/3-44).
% Contract: receiver = equalizer(channel, source, cfg).
% channel.received is one data block [data, UW]; known channel from impulse.
N = numel(channel.received);
cfg = scfde.equalizers.ch3_setup(cfg, N, numel(source.data));
H = fft([channel.impulse(:).', zeros(1, N - numel(channel.impulse))]);
X = scfde.equalizers.ch3_mmse_frequency_equalize(fft(channel.received), ...
    H, cfg.noiseVariance);
symbols = ifft(X);
decisions = scfde.equalizers.ch3_qpsk_map( ...
    scfde.equalizers.ch3_qpsk_demap(symbols(1:cfg.dataSymbols)));
trace.H = H;
receiver = scfde.equalizers.pack_equalizer("MMSE-SC-FDE", "mmse-fde", ...
    decisions, abs(symbols(1:cfg.dataSymbols) - source.data).^2, ...
    symbols(1:cfg.dataSymbols), trace);
end
