function receiver = ptr_dfe(channel, source, cfg)
%PTR_DFE Passive time-reversal (PTR) front end + known DFE (book 2-47).
%   Book path: y(n) = h*(-n) * r(n)  (linear convolution matched
%   filter, eq. 2-47).  The focused output is delay-aligned to the main
%   tap of the time-reversed filter and fed into the known-channel DFE.
%   The equivalent channel for the DFE is Q(t) = h*(-t) * h(t).
%   The previous circular (frequency-domain) front end is kept in
%   ptr_circular_engineering.m (BOOK_CONVENTIONS.md rule 2).
N = numel(channel.received);
impulse = channel.impulse(:).';
% Trim the zero-padded N-long impulse to its active span so the matched
% filter and the equivalent channel keep a compact length: the known-DFE
% MMSE target sits at the equivalent-channel main tap, and with the N
% zero-padding that tap lands at index ~N/2 while the solver only allows
% a delay of feedforwardTaps-1 (11), putting the target in the zero
% guard region and forcing a zero weight solution (BER ~ 0.5).
nzFirst = find(abs(impulse) > 0, 1, "first");
nzLast = find(abs(impulse) > 0, 1, "last");
impulseShort = impulse(nzFirst:nzLast);
timeReversal = conj(fliplr(impulseShort));            % h*(-n)
ptrFrontEndFull = conv(timeReversal, channel.received);
% Matched-filter peak alignment: the main tap of h*(-n) (conj(h_0))
% lands at output position L = numel(h), aligned with r(0); the DFE
% stage then treats that tap as delay 0.
L = numel(impulseShort);
ptrFrontEnd = ptrFrontEndFull(L:L + N - 1);
equivalent = conv(timeReversal, impulseShort);        % Q(t) = h*(-t)*h(t)
[decisions, mse, ~, trace] = scfde.equalizers.known_dfe_core( ...
    ptrFrontEnd, source.tx, equivalent, cfg);
receiver = scfde.equalizers.pack_equalizer("Passive TR-DFE", "ptr-dfe", ...
    decisions, mse, ptrFrontEnd, trace);
end
