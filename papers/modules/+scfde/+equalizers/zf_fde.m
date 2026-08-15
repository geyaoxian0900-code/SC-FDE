function receiver = zf_fde(channel, source, cfg)
%ZF_FDE Frequency-domain zero-forcing equalizer module
% (book (3-43)/(3-44) zero-noise limit; spec 3.2: C_k = 1/(lambda H_k)).
%   Strict ZF: NO epsilon floor on the division.  Frequency bins where
%   the channel vanishes are REPORTED in trace.singularBins - strict ZF
%   does not exist at H_k = 0 (spec 3.2); the regularized form
%   H_k*/(|H_k|^2 + eps) would be an ENGINEERING extension and is not
%   used.  lambda = 1 in the zero-Doppler scenario (Phi ~ I per
%   (3-39)~(3-41)); recorded in the trace.
N = numel(channel.received);
cfg = scfde.equalizers.ch3_setup(cfg, N, numel(source.data));
H = fft([channel.impulse(:).', zeros(1, N - numel(channel.impulse))]);
lambda = 1;                     % zero-Doppler scenario: Phi ~ I
X = fft(channel.received) ./ (lambda .* H);
symbols = ifft(X);
decisions = scfde.equalizers.ch3_qpsk_map( ...
    scfde.equalizers.ch3_qpsk_demap(symbols(1:cfg.dataSymbols)));
trace.H = H;
trace.lambda = lambda;
trace.singularBins = find(abs(H) < eps);
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = struct("fftSize", cfg.fftSize, ...
    "dataSymbols", cfg.dataSymbols, "lambda", lambda);
trace.formulaNote = "(3-43)/(3-44) zero-noise limit: C_k = 1/(lambda H_k); no epsilon floor, singular bins reported (strict ZF undefined at H_k = 0)";
receiver = scfde.equalizers.pack_equalizer("ZF-SC-FDE", "zf-fde", ...
    decisions, abs(symbols(1:cfg.dataSymbols) - source.data).^2, ...
    symbols(1:cfg.dataSymbols), trace);
end
