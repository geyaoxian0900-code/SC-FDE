function value = logadd(left, right)
maximum = max(left, right);
if isinf(maximum)
    value = maximum;
else
    value = maximum + log1p(exp(min(left, right) - maximum));
end
end
