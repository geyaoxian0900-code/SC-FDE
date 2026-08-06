function inverseCorrelation = initial_inverse_correlation(weightCount, cfg, updateRule)
%INITIAL_INVERSE_CORRELATION Shared RLS initialization for the equalizer package.
if updateRule == "rls"
    inverseCorrelation = cfg.rlsInitialInverseCorrelation * eye(weightCount);
else
    inverseCorrelation = [];
end
end
