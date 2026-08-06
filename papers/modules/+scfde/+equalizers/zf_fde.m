function receiver = zf_fde(channel, source, cfg)
%ZF_FDE Frequency-domain zero-forcing equalizer module (book 3-25).
N = numel(channel.received);
cfg = scfde.equalizers.ch3_setup(cfg, N, numel(source.data));
H = fft([channel.impulse(:).', zeros(1, N - numel(channel.impulse))]);
X = fft(channel.received) ./ max(H, eps);
symbols = ifft(X);
decisions = scfde.equalizers.ch3_qpsk_map( ...
    scfde.equalizers.ch3_qpsk_demap(symbols(1:cfg.dataSymbols)));
trace.H = H;
receiver = scfde.equalizers.pack_equalizer("ZF-SC-FDE", "zf-fde", ...
    decisions, abs(symbols(1:cfg.dataSymbols) - source.data).^2, ...
    symbols(1:cfg.dataSymbols), trace);
end
