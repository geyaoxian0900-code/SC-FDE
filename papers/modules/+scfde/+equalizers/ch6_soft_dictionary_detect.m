function [decision, expected, metric, posterior] = ch6_soft_dictionary_detect( ...
        observation, dictionary, variance, logPrior)
if isscalar(variance)
    variance = repmat(variance, 1, size(dictionary, 2));
end
variance = max(real(variance(:).'), 1e-10);
distance = sum(abs(dictionary - observation).^2 ./ variance, 2);
metric = -distance + logPrior(:);
metric = scfde.equalizers.ch6_normalize_log(metric);
[~, decision] = max(metric);
posterior = exp(metric);
posterior = posterior / sum(posterior);
expected = posterior.' * dictionary;
end
