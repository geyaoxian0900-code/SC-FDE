function receiver = ptr_dfe(channel, source, cfg)
%PTR_DFE Passive time-reversal (PTR) front end + known DFE (book 2-47).
% The PTR front end is the CIRCULAR matched filter (frequency-domain
% time reversal): the received block is a circular convolution of the
% transmit block with the channel, so the linear filter(tr,1,.) would
% spread the focused energy; the circular front end delivers one
% correlation peak per symbol.
N = numel(channel.received);
timeReversal = conj(fliplr(channel.impulse));
ptrFrontEnd = ifft(conj(fft(channel.impulse, N)) .* fft(channel.received));
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
