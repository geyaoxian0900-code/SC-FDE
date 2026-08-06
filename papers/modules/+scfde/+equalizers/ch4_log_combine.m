function value = ch4_log_combine(left, right, mode)
if mode == "Max-Log-MAP"
    value = max(left, right);
    return;
end
maximum = max(left, right);
if isinf(maximum)
    value = maximum;
else
    value = maximum + log(exp(left - maximum) + exp(right - maximum));
end
end