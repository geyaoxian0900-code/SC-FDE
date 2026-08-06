function receiver = custom_matched_filter(channel, source, cfg)
%CUSTOM_MATCHED_FILTER Example plug-in equalizer module: matched filter + slicing.
% Demonstrates the equalizer module contract
%   receiver = equalizer(channel, source, cfg)
% A custom equalizer only needs to return receiver.outputs{1} (symbol
% estimates aligned with source.tx) plus ids/names; traces are optional.

impulse = channel.impulse;
matched = conj(fliplr(impulse));
filtered = filter(matched, 1, channel.received);
delay = floor(numel(impulse) / 2);
estimates = zeros(size(source.tx));
for symbolIndex = 1:numel(source.tx)
    index = symbolIndex + delay;
    if index <= numel(filtered)
        estimates(symbolIndex) = filtered(index);
    end
end
decisions = sign(real(estimates));
decisions(decisions == 0) = 1;

receiver.names = "Matched filter (custom)";
receiver.ids = "custom-matched-filter";
receiver.outputs = {decisions};
receiver.learningMse = {abs(estimates - source.tx).^2};
receiver.estimates = {estimates};
receiver.traces = {struct("delay", delay)};
receiver.requestedMethods = "custom-matched-filter";
end
