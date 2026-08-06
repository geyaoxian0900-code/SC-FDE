function metrics = metric_ber(receiver, source, cfg)
%METRIC_BER Compute payload BER for every receiver in a receiver bank.
% Compatible with two output conventions:
%   - full-frame outputs (length == numel(source.tx)): payload = training+1:end
%   - data-only outputs (length == numel(source.data)): payload = 1:end

metrics.ber = zeros(1, numel(receiver.outputs));
metrics.errorCount = zeros(1, numel(receiver.outputs));
metrics.symbolCount = zeros(1, numel(receiver.outputs));
fullFrame = numel(source.tx);
dataOnly = numel(source.data);
trainingSymbols = 0;
if isfield(cfg, "trainingSymbols")
    trainingSymbols = cfg.trainingSymbols;
end
for receiverIndex = 1:numel(receiver.outputs)
    output = receiver.outputs{receiverIndex}(:).';
    if numel(output) == fullFrame && fullFrame > dataOnly
        payload = min(trainingSymbols + 1, dataOnly + 1):fullFrame;
    elseif numel(output) == dataOnly
        payload = 1:dataOnly;
    else
        payload = 1:min(numel(output), dataOnly);
    end
    decisions = output(payload);
    reference = source.data(1:numel(payload));
    valid = decisions ~= 0 & reference ~= 0;
    metrics.errorCount(receiverIndex) = sum(decisions(valid) ~= reference(valid));
    metrics.symbolCount(receiverIndex) = sum(valid);
    metrics.ber(receiverIndex) = metrics.errorCount(receiverIndex) / ...
        max(metrics.symbolCount(receiverIndex), 1);
end
end
