function receiver = ptr_dfe(channel, source, cfg)
%PTR_DFE Passive time-reversal (PTR) front end + known DFE (book 2-47).
timeReversal = conj(fliplr(channel.impulse));
ptrFrontEnd = filter(timeReversal, 1, channel.received);
[decisions, mse, ~, trace] = scfde.equalizers.known_dfe_core( ...
    ptrFrontEnd, source.tx, ...
    conv(timeReversal, channel.impulse), cfg);
% The PTR front-end output IS the soft output of the passive
% time-reversal (matched-filter) processing: the DFE stage may not
% converge when the time-reversed equivalent impulse exceeds the
% feedforward span (its estimates are then zero), but the PTR soft
% output always carries the multi-path structure.
receiver = scfde.equalizers.pack_equalizer("Passive TR-DFE", "ptr-dfe", ...
    decisions, mse, ptrFrontEnd, trace);
end
