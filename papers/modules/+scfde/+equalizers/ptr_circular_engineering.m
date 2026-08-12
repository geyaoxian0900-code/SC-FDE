function receiver = ptr_circular_engineering(channel, source, cfg)
%PTR_CIRCULAR_ENGINEERING Circular PTR front end + known DFE.
%   ENGINEERING variant (BOOK_CONVENTIONS.md rule 2): the book defines
%   the linear filter y = h*(-n) * r(n) (eq. 2-47); the circular
%   frequency-domain time reversal below is an engineering substitute
%   for block-circulant frames.  The book path is ptr_dfe.m.
N = numel(channel.received);
timeReversal = conj(fliplr(channel.impulse));
ptrFrontEnd = ifft(conj(fft(channel.impulse, N)) .* fft(channel.received));
[decisions, mse, ~, trace] = scfde.equalizers.known_dfe_core( ...
    ptrFrontEnd, source.tx, ...
    conv(timeReversal, channel.impulse), cfg);
receiver = scfde.equalizers.pack_equalizer("Passive TR-DFE (circular)", ...
    "ptr-circular-engineering", decisions, mse, ptrFrontEnd, trace);
end
