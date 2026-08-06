function receiver = ice_sd_ibdfe(channel, source, cfg)
%ICE_SD_IBDFE Iterative channel estimation + soft IBDFE module (3-88~3-92).
% Constructs a self-consistent training pair from the known impulse:
%   training (ZC) -> H -> receivedTraining, then ICE refines H jointly
%   with soft feedback from the data block.
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
    cfg.noiseVariance, uw, cfg, "soft", true);
decisions = scfde.equalizers.ch3_qpsk_map( ...
    scfde.equalizers.ch3_qpsk_demap(symbols(1:cfg.dataSymbols)));
trace.H = H;
receiver = scfde.equalizers.pack_equalizer("ICE-SD-IBDFE", "ice-sd-ibdfe", ...
    decisions, abs(symbols(1:cfg.dataSymbols) - source.data).^2, ...
    symbols(1:cfg.dataSymbols), trace);
end
