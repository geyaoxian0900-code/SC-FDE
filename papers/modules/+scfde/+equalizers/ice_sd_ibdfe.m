function receiver = ice_sd_ibdfe(channel, source, cfg)
%ICE_SD_IBDFE Iterative channel estimation + soft IBDFE module (3-88~3-92).
%   Initial H comes from the training/knowledge channel estimate (the
%   scenario contract passes channel.impulse); the data-driven channel
%   updates follow (3-88)~(3-92) from iteration 2 onward inside
%   ch3_ibdfe_equalize (no training-observation synthesis, no RNG use).
N = numel(channel.received);
cfg = scfde.equalizers.ch3_setup(cfg, N, numel(source.data));
uw = scfde.equalizers.ch3_zadoff_chu(cfg.uwLength, 1);
H = fft([channel.impulse(:).', zeros(1, N - numel(channel.impulse))]);
training = scfde.equalizers.ch3_zadoff_chu(N, 1);
[symbols, trace, H] = scfde.equalizers.ch3_ibdfe_equalize( ...
    channel.received, [], training, H, ...
    cfg.noiseVariance, uw, cfg, "soft", true);
decisions = scfde.equalizers.ch3_qpsk_map( ...
    scfde.equalizers.ch3_qpsk_demap(symbols(1:cfg.dataSymbols)));
trace.H = H;
trace.initialChannelSource = "training/knowledge: H from channel.impulse (scenario contract)";
trace.rngTransparent = true;
receiver = scfde.equalizers.pack_equalizer("ICE-SD-IBDFE", "ice-sd-ibdfe", ...
    decisions, abs(symbols(1:cfg.dataSymbols) - source.data).^2, ...
    symbols(1:cfg.dataSymbols), trace);
end
