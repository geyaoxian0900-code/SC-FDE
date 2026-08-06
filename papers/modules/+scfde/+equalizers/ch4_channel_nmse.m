function nmse = channel_nmse(estimate, reference)
nmse = sum(abs(estimate - reference).^2) / ...
    max(sum(abs(reference).^2), eps);
end
