function source = source_qpsk(cfg)
%SOURCE_QPSK QPSK source module: training + data, tx = [training, data].
training = exp(1j * 2 * pi * rand(1, cfg.trainingSymbols));
data = ((2 * randi([0, 1], 1, cfg.dataSymbols) - 1) + ...
    1j * (2 * randi([0, 1], 1, cfg.dataSymbols) - 1)) / sqrt(2);
source.training = training;
source.data = data;
source.tx = [training, data];
end
