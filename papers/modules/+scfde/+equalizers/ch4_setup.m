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
