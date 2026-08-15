function receiver = rls_dfe(channel, source, cfg)
%RLS_DFE RLS adaptive DFE equalizer module (book (2-18)~(2-25)).
[decisions, mse, estimates, trace] = scfde.equalizers.adaptive_dfe_core( ...
    channel.received, source.tx, cfg, "rls", false);
% (2-23)~(2-25): k = P u/(lambda + u^H P u); w += k e*;
% P = lambda^-1 (P - k u^H P).  Initialization is a numerical choice
% recorded here (not claimed as the book's unique value).
trace.updateEquation = "(2-23)~(2-25) RLS: k=P u/(lambda+u^H P u), w+=k e*, P=lambda^-1(P-k u^H P)";
trace.stepParameters = struct("lambda", cfg.rlsForgettingFactor, ...
    "pInitialScale", cfg.rlsInitialInverseCorrelation, ...
    "p0", "delta^-1 I (delta^-1 = cfg.rlsInitialInverseCorrelation)", ...
    "feedforwardTaps", cfg.feedforwardTaps, ...
    "feedbackTaps", cfg.feedbackTaps);
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = trace.stepParameters;
receiver = scfde.equalizers.pack_equalizer("RLS adaptive DFE", "rls-dfe", ...
    decisions, mse, estimates, trace);
end
