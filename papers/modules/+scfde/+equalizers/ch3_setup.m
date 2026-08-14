function cfg = ch3_setup(cfg, blockLength, dataSymbols)
%CH3_SETUP Normalize Chapter 3 equalizer options for the unified contract.
if isfield(cfg, "fftSize") && cfg.fftSize ~= blockLength
    cfg.fftSize = blockLength;
end
cfg.fftSize = blockLength;
cfg.dataSymbols = dataSymbols;
cfg.uwLength = blockLength - dataSymbols;
if ~isfield(cfg, "channelEstimateLength") || cfg.channelEstimateLength <= 0
    cfg.channelEstimateLength = min(16, floor(blockLength / 8));
end
if ~isfield(cfg, "htfdeBranches") || cfg.htfdeBranches <= 0
    cfg.htfdeBranches = 4;
end
if ~isfield(cfg, "htfdeIterations") || cfg.htfdeIterations <= 0
    cfg.htfdeIterations = 3;
end
if ~isfield(cfg, "ibdfeIterations") || cfg.ibdfeIterations <= 0
    cfg.ibdfeIterations = 4;
end
if ~isfield(cfg, "channelRegularization")
    cfg.channelRegularization = 0.1;
end
if ~isfield(cfg, "noiseVariance") || cfg.noiseVariance <= 0
    cfg.noiseVariance = 10^(-cfg.snrDb / 10);
end
% The legacy segmented (engineering) HTFDE variant splits the block into
% htfdeBranches segments, so its block length must be divisible; the BOOK
% (3-61)/(3-62) path does not segment and skips this precondition.
if ~(isfield(cfg, "htfdeMode") && strcmpi(cfg.htfdeMode, "book"))
    assert(mod(cfg.fftSize, cfg.htfdeBranches) == 0, ...
        "SCFDE:BlockSize", "Block length must be divisible by htfdeBranches.");
end
end
