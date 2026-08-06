function row = ch4_normalize_log_row(row)
maximum = max(row);
if isfinite(maximum)
    row = row - maximum;
end
end
