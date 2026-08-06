function receiver = ice_hd_ibdfe(channel, source, cfg)
%ICE_HD_IBDFE Iterative channel estimation + hard IBDFE module (3-88~3-92).
N = numel(channel.received);
cfg = scfde.equalizers.ch3_setup(cfg, N, numel(source.data));
uw = scfde.equalizers.ch3_zadoff_chu(cfg.uwLength, 1);
H = fft([channel.impulse(:).', zeros(1, N - numel(channel.impulse))]);
training = scfde.equalizers.ch3_zadoff_chu(N, 1);
receivedTraining = ifft(H .* fft(training));
receivedTraining = receivedTraining + sqrt(cfg.noiseVariance / 2) * ...
    (randn(size(receivedTraining)) + 1j * randn(size(receivedTraining)));
[symbols, trace, H] = scfde.equalizers.ch3_ibdfe_equalize( ...
    channel.received, receivedTraining, training, H, ...
    cfg.noiseVariance, uw, cfg, "hard", true);
decisions = scfde.equalizers.ch3_qpsk_map( ...
    scfde.equalizers.ch3_qpsk_demap(symbols(1:cfg.dataSymbols)));
trace.H = H;
receiver = scfde.equalizers.pack_equalizer("ICE-HD-IBDFE", "ice-hd-ibdfe", ...
    decisions, abs(symbols(1:cfg.dataSymbols) - source.data).^2, ...
    symbols(1:cfg.dataSymbols), trace);
end
