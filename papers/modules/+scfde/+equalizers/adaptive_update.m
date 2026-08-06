function [weights, inverseCorrelation] = adaptive_update(weights, inverseCorrelation, ...
        input, error, cfg, updateRule)
%ADAPTIVE_UPDATE Shared adaptive update rules (2-14)/(2-16)/(2-23)-(2-25).
switch updateRule
    case "lms"
        weights = weights + cfg.lmsStep * input * conj(error);
    case "nlms"
        weights = weights + cfg.nlmsStep * input * conj(error) / ...
            (real(input' * input) + 1e-5);
    case "rls"
        forgettingFactor = cfg.rlsForgettingFactor;
        gain = inverseCorrelation * input / (forgettingFactor + ...
            real(input' * inverseCorrelation * input));
        weights = weights + gain * conj(error);
        inverseCorrelation = (inverseCorrelation - ...
            gain * input' * inverseCorrelation) / forgettingFactor;
        inverseCorrelation = (inverseCorrelation + inverseCorrelation') / 2;
    otherwise
        error("SCFDE:UnknownAdaptiveRule", ...
            "Unknown adaptive update rule: %s", updateRule);
end
end
