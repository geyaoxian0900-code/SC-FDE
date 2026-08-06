function value = ch5_log_sum_exp(values)
maximum = max(values);
value = maximum + log(sum(exp(values - maximum)));
end
