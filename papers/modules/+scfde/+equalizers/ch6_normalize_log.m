function output = ch6_normalize_log(values)
maximum = max(values(:));
if isfinite(maximum)
    output = values - maximum;
else
    output = values;
end
end
