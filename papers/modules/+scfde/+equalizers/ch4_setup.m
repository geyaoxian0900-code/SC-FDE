function cfg = ch4_setup(cfg, blockLength)
%CH4_SETUP Normalize Chapter 4 equalizer options with defaults.
if isfield(cfg, "noiseVariance") && ~isempty(cfg.noiseVariance) && cfg.noiseVariance > 0
    nv = cfg.noiseVariance;
elseif isfield(cfg, "snrDb")
    nv = 10^(-cfg.snrDb / 10);
else
    nv = 0.01;
end
cfg.noiseVariance = nv;
if ~isfield(cfg, "turboDecoderMode"), cfg.turboDecoderMode = "Log-MAP"; end
if ~isfield(cfg, "baselineDecoder"), cfg.baselineDecoder = "Log-MAP"; end
if ~isfield(cfg, "iterations"), cfg.iterations = 4; end
if ~isfield(cfg, "infoBits"), cfg.infoBits = blockLength / 2; end
if ~isfield(cfg, "tdAdaptiveTaps"), cfg.tdAdaptiveTaps = 16; end
if ~isfield(cfg, "tdNlmsStep"), cfg.tdNlmsStep = 0.35; end
% Step selected with reference to the independence-based mean-convergence
% diagnostic for the spec-4.8 UNNORMALIZED LMS: the NLMS-era
% tdNlmsStep=0.35 exceeds the joint-regressor MEAN-convergence reference
% 2/lambda_max(R_hat), u_n = [r_n; -x_bar_{n-1}] (measured ~0.096 on
% the unit-energy 16-tap turbo input at 18 dB) and diverges.  tddaMu
% defaults to 0.05, which is about HALF that reference; the reference is
% measured PER ROUND inside ch4_iterate_td_nlms_turbo and recorded in
% trace.meanConvergenceBound / trace.withinMeanConvergenceBound
% (per-round arrays; theoretical diagnostic only, NOT a stability
% guarantee - the overall diagnostic meanBoundSatisfiedAllIterations
% uses the minimum across rounds).
if ~isfield(cfg, "tddaMu"), cfg.tddaMu = 0.05; end
if ~isfield(cfg, "feedbackTaps"), cfg.feedbackTaps = 6; end
if ~isfield(cfg, "feedforwardTaps"), cfg.feedforwardTaps = 12; end
if ~isfield(cfg, "blmsStep"), cfg.blmsStep = 0.06; end
if ~isfield(cfg, "blmsLeakage"), cfg.blmsLeakage = 1e-3; end
if ~isfield(cfg, "blmsRegularization"), cfg.blmsRegularization = 1e-3; end
if ~isfield(cfg, "turboDamping"), cfg.turboDamping = 1; end
% BOOK parameter lock: the book defines NO soft-feedback damping
% (feedback uses the decoder soft symbols directly, eq. 4-47/4-49),
% so the default is alpha = 1 (undamped).  Engineering studies may
% override cfg.turboDamping explicitly (e.g. run_chapter4_turbo_suite
% defaults to 0.75); the unified book path stays undamped.
end
