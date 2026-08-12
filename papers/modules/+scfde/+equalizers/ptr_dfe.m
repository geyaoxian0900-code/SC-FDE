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
timeReversal = conj(fliplr(impulse));            % h*(-n)
ptrFrontEndFull = conv(timeReversal, channel.received);
% Matched-filter peak alignment: the main tap of h*(-n) (conj(h_0))
% lands at output position L = numel(h), aligned with r(0); the DFE
% stage then treats that tap as delay 0.  (Using max(|h|) here was a
% bug: fliplr moves h_0 to the END of the vector.)
L = numel(impulse);
ptrFrontEnd = ptrFrontEndFull(L:L + N - 1);
equivalent = conv(timeReversal, impulse);        % Q(t) = h*(-t)*h(t)
[decisions, mse, ~, trace] = scfde.equalizers.known_dfe_core( ...
    ptrFrontEnd, source.tx, equivalent, cfg);
receiver = scfde.equalizers.pack_equalizer("Passive TR-DFE", "ptr-dfe", ...
    decisions, mse, ptrFrontEnd, trace);
end
