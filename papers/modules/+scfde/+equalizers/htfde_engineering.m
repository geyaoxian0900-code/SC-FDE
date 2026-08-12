function receiver = htfde_engineering(channel, source, cfg)
%HTFDE_ENGINEERING HTFDE with engineering reliability scaling.
%   ENGINEERING variant of htfde.m (BOOK_CONVENTIONS.md rule 2):
%   applies posterior-mean reliability weighting to the feedback
%   cancellation, which the book does not define.  Kept only for
%   comparison studies; the book path is htfde.m.
%   Contract: receiver = equalizer(channel, source, cfg).
N = numel(channel.received);
cfg = scfde.equalizers.ch3_setup(cfg, N, numel(source.data));
uw = scfde.equalizers.ch3_zadoff_chu(cfg.uwLength, 1);
H = fft([channel.impulse(:).', zeros(1, N - numel(channel.impulse))]);
[symbols, trace] = scfde.equalizers.ch3_htfde_equalize_engineering( ...
    channel.received, H, cfg.noiseVariance, uw, cfg);
decisions = scfde.equalizers.ch3_qpsk_map( ...
    scfde.equalizers.ch3_qpsk_demap(symbols(1:cfg.dataSymbols)));
receiver = scfde.equalizers.pack_equalizer("HTFDE-ENGINEERING", "htfde-engineering", ...
    decisions, abs(symbols(1:cfg.dataSymbols) - source.data).^2, ...
    symbols(1:cfg.dataSymbols), trace);
end
