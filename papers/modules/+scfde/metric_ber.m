function metrics = metric_ber(receiver, source, cfg)
%METRIC_BER Compute payload BER for every receiver in a receiver bank.

metrics.ber = zeros(1, numel(receiver.outputs));
metrics.errorCount = zeros(1, numel(receiver.outputs));
metrics.symbolCount = zeros(1, numel(receiver.outputs));
payload = cfg.trainingSymbols + 1:numel(source.tx);
for receiverIndex = 1:numel(receiver.outputs)
    decisions = receiver.outputs{receiverIndex}(payload);
    valid = decisions ~= 0;
    metrics.errorCount(receiverIndex) = sum(decisions(valid) ~= source.data(valid));
    metrics.symbolCount(receiverIndex) = sum(valid);
    metrics.ber(receiverIndex) = metrics.errorCount(receiverIndex) / ...
        metrics.symbolCount(receiverIndex);
end
end
