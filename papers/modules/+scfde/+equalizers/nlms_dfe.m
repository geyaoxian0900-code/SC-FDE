function receiver = nlms_dfe(channel, source, cfg)
%NLMS_DFE NLMS adaptive DFE equalizer module (book 2.2.2, (2-16)).
[decisions, mse, estimates, trace] = scfde.equalizers.adaptive_dfe_core( ...
    channel.received, source.tx, cfg, "nlms", false);
% (2-16): w(n+1) = w(n) + mu e*(n) u(n) / (delta + u^H u); delta = 1e-5
% is a zero-division guard only (no SNR/channel-energy floors); the
% feedforward and feedback taps share ONE composite update.
trace.updateEquation = "(2-16) w(n+1)=w(n)+mu e*(n) u(n)/(delta+u^H u), delta=1e-5";
trace.stepParameters = struct("nlmsStepMu", cfg.nlmsStep, "delta", 1e-5, ...
    "feedforwardTaps", cfg.feedforwardTaps, ...
    "feedbackTaps", cfg.feedbackTaps);
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = trace.stepParameters;
receiver = scfde.equalizers.pack_equalizer("NLMS adaptive DFE", "nlms-dfe", ...
    decisions, mse, estimates, trace);
end
