function receiver = lms_dfe(channel, source, cfg)
%LMS_DFE LMS adaptive DFE equalizer module (book (2-12)~(2-15)).
[decisions, mse, estimates, trace] = scfde.equalizers.adaptive_dfe_core( ...
    channel.received, source.tx, cfg, "lms", false);
% (2-14): w(n+1) = w(n) + 2*mu*e*(n)*u(n); cfg.lmsStep corresponds to
% the whole 2*mu_book factor of the boxed update.
trace.updateEquation = "(2-14) w(n+1)=w(n)+2mu e*(n) u(n); cfg.lmsStep = 2mu_book";
trace.stepParameters = struct("lmsStep2mu", cfg.lmsStep, ...
    "feedforwardTaps", cfg.feedforwardTaps, ...
    "feedbackTaps", cfg.feedbackTaps);
trace.formulaStatus = "BOOK-EXACT";
trace.formulaMode = "book";
trace.bookExperimentEquivalent = false;
trace.effectiveParameters = trace.stepParameters;
receiver = scfde.equalizers.pack_equalizer("LMS adaptive DFE", "lms-dfe", ...
    decisions, mse, estimates, trace);
end
