function source = source_bpsk(cfg)
%SOURCE_BPSK Generate training and payload symbols for SC-TDE experiments.

source.training = 2 * randi([0, 1], 1, cfg.trainingSymbols) - 1;
source.data = 2 * randi([0, 1], 1, cfg.dataSymbols) - 1;
source.tx = [source.training, source.data];
end
